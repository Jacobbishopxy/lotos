#!/usr/bin/env python3
"""CPU/RSS load generator for TaskSchedule mock tasks.

The helper is intentionally dependency-free so task TOML can invoke it directly
from a worker with Python 3 available. It is for scheduler and dashboard smoke
work, not for hard resource enforcement tests.
"""

from __future__ import annotations

import argparse
import json
import multiprocessing as mp
import os
from pathlib import Path
import signal
import sys
import time
from typing import Optional, Tuple

MIB = 1024 * 1024


def positive_int(raw: str) -> int:
    value = int(raw)
    if value < 0:
        raise argparse.ArgumentTypeError("must be non-negative")
    return value


def percent(raw: str) -> float:
    value = float(raw)
    if value < 0 or value > 100:
        raise argparse.ArgumentTypeError("must be between 0 and 100")
    return value


def read_cgroup_int(path: str) -> Optional[int]:
    try:
        raw = Path(path).read_text(encoding="utf-8").strip()
    except OSError:
        return None
    if not raw or raw == "max":
        return None
    try:
        value = int(raw)
    except ValueError:
        return None
    # cgroup v1 commonly reports a huge sentinel when no limit is configured.
    if value <= 0 or value >= 1 << 60:
        return None
    return value


def host_memory_bytes() -> int:
    try:
        return int(os.sysconf("SC_PAGE_SIZE")) * int(os.sysconf("SC_PHYS_PAGES"))
    except (AttributeError, OSError, ValueError):
        # Fallback keeps the helper usable on unusual systems while staying safe.
        return 1024 * MIB


def cgroup_memory_limit_bytes() -> Optional[int]:
    candidates = [
        "/sys/fs/cgroup/memory.max",  # cgroup v2
        "/sys/fs/cgroup/memory/memory.limit_in_bytes",  # cgroup v1
    ]
    limits = [value for path in candidates if (value := read_cgroup_int(path)) is not None]
    if not limits:
        return None
    return min(limits)


def memory_basis_bytes(mode: str) -> Tuple[int, str]:
    host = host_memory_bytes()
    cgroup = cgroup_memory_limit_bytes()
    if mode == "host":
        return host, "host"
    if mode == "cgroup":
        return (cgroup, "cgroup") if cgroup is not None else (host, "host-fallback")
    if cgroup is not None and cgroup < host:
        return cgroup, "cgroup"
    return host, "host"


def cpu_burn(stop_event: mp.Event, worker_index: int) -> None:
    # A simple integer loop avoids sleeping and keeps one process near 100% CPU.
    value = 0x9E3779B9 ^ worker_index
    while not stop_event.is_set():
        for _ in range(100_000):
            value = (value * 1664525 + 1013904223) & 0xFFFFFFFF
    # Make the loop state observable to prevent over-eager optimization in other
    # Python runtimes while remaining harmless under CPython.
    if value == -1:  # pragma: no cover
        print(value)


def resolve_target_mib(args: argparse.Namespace) -> Tuple[int, dict[str, object]]:
    basis_bytes, basis_name = memory_basis_bytes(args.mem_basis)
    if args.mem_mb is not None:
        requested_mib = args.mem_mb
        requested_from = "mem-mb"
    else:
        requested_mib = int((basis_bytes * (args.mem_percent / 100.0)) / MIB)
        requested_from = "mem-percent"

    cap_applied = False
    target_mib = requested_mib
    if args.max_rss_mb > 0 and target_mib > args.max_rss_mb:
        target_mib = args.max_rss_mb
        cap_applied = True

    details = {
        "basis": basis_name,
        "basisMiB": round(basis_bytes / MIB, 2),
        "requestedFrom": requested_from,
        "requestedMemMiB": requested_mib,
        "maxRssMiB": args.max_rss_mb,
        "capApplied": cap_applied,
    }
    return max(0, target_mib), details


def allocate_memory(target_mib: int, chunk_mib: int, stop_event: mp.Event) -> Tuple[list[bytearray], int]:
    held: list[bytearray] = []
    target_bytes = target_mib * MIB
    chunk_bytes = max(1, chunk_mib) * MIB
    allocated = 0
    while allocated < target_bytes and not stop_event.is_set():
        this_chunk = min(chunk_bytes, target_bytes - allocated)
        block = bytearray(this_chunk)
        # Touch every page so RSS follows the requested allocation instead of
        # remaining mostly virtual memory.
        for offset in range(0, len(block), 4096):
            block[offset] = 1
        held.append(block)
        allocated += this_chunk
    return held, allocated // MIB


def write_summary(path: Optional[str], summary: dict[str, object]) -> None:
    if not path:
        return
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Burn configurable CPU workers and RSS for TaskSchedule mock tasks.")
    parser.add_argument("--duration-sec", type=positive_int, default=60, help="wall-clock seconds to hold the load")
    parser.add_argument("--cpu-workers", type=positive_int, default=1, help="processes to spin; N ~= N*100%% CPU")
    parser.add_argument("--mem-percent", type=percent, default=0.0, help="percent of selected memory basis to allocate")
    parser.add_argument("--mem-mb", type=positive_int, default=None, help="absolute MiB to allocate; overrides --mem-percent")
    parser.add_argument("--max-rss-mb", type=positive_int, default=4096, help="safety cap for target allocation; 0 disables the cap")
    parser.add_argument("--mem-basis", choices=["auto", "host", "cgroup"], default="auto", help="memory total used for --mem-percent")
    parser.add_argument("--chunk-mb", type=positive_int, default=64, help="allocation chunk size in MiB")
    parser.add_argument("--report-every-sec", type=positive_int, default=5, help="stdout progress interval; 0 disables progress")
    parser.add_argument("--output", default=None, help="write JSON completion summary to this path")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    stop_event = mp.Event()

    def request_stop(signum: int, _frame: object) -> None:
        print(f"received signal {signum}; stopping resource burner", flush=True)
        stop_event.set()

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    target_mib, mem_details = resolve_target_mib(args)
    start = time.time()
    started_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(start))
    summary: dict[str, object] = {
        "status": "starting",
        "startedAt": started_at,
        "durationSec": args.duration_sec,
        "cpuWorkers": args.cpu_workers,
        "targetMemMiB": target_mib,
        **mem_details,
    }

    print(
        "resource-burner plan: "
        f"cpuWorkers={args.cpu_workers} (~{args.cpu_workers}*100% CPU) "
        f"targetMemMiB={target_mib} durationSec={args.duration_sec} "
        f"basis={mem_details['basis']} capApplied={mem_details['capApplied']}",
        flush=True,
    )

    workers = [mp.Process(target=cpu_burn, args=(stop_event, index), daemon=True) for index in range(args.cpu_workers)]
    for process in workers:
        process.start()

    held_memory: list[bytearray] = []
    allocated_mib = 0
    try:
        held_memory, allocated_mib = allocate_memory(target_mib, args.chunk_mb, stop_event)
        summary["allocatedMemMiB"] = allocated_mib
        print(f"resource-burner allocated {allocated_mib} MiB and is holding load", flush=True)

        deadline = time.monotonic() + args.duration_sec
        while not stop_event.is_set():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            sleep_for = min(remaining, args.report_every_sec if args.report_every_sec > 0 else remaining)
            time.sleep(max(0.0, sleep_for))
            if args.report_every_sec > 0 and remaining > sleep_for:
                elapsed = round(time.time() - start, 1)
                print(f"resource-burner progress: elapsedSec={elapsed} holdingMemMiB={allocated_mib}", flush=True)

        summary["status"] = "interrupted" if stop_event.is_set() else "completed"
    except MemoryError:
        summary["status"] = "memory-error"
        summary["allocatedMemMiB"] = allocated_mib
        print(f"resource-burner failed with MemoryError after {allocated_mib} MiB", file=sys.stderr, flush=True)
    finally:
        stop_event.set()
        for process in workers:
            process.join(timeout=5)
            if process.is_alive():
                process.terminate()
                process.join(timeout=2)
        summary["finishedAt"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        summary["elapsedSec"] = round(time.time() - start, 3)
        summary.setdefault("allocatedMemMiB", allocated_mib)
        summary["workerExitCodes"] = [process.exitcode for process in workers]
        write_summary(args.output, summary)
        # Keep the memory live until workers have stopped and the summary is
        # written; then let Python release it on process exit.
        _ = held_memory

    print("resource-burner summary: " + json.dumps(summary, sort_keys=True), flush=True)
    if summary["status"] == "completed":
        return 0
    if summary["status"] == "interrupted":
        return 130
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
