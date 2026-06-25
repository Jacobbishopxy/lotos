#!/usr/bin/env python3
"""Generate TaskSchedule config profiles from the checked-in loopback configs.

The bind-all profile intentionally separates bind addresses from connect
addresses. 0.0.0.0 is valid for broker/HTTP/bridge binds, but workers and
clients should connect to a concrete host or DNS name.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit


def rewrite_tcp_host(endpoint: str, host: str) -> str:
    if not endpoint.startswith("tcp://"):
        return endpoint
    parts = urlsplit(endpoint)
    if not parts.port:
        raise ValueError(f"TCP endpoint must include a port: {endpoint}")
    return urlunsplit((parts.scheme, f"{host}:{parts.port}", parts.path, parts.query, parts.fragment))


def read_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2)
        handle.write("\n")


def origin_hosts(connect_host: str, dashboard_origin_host: str | None) -> list[str]:
    hosts = ["127.0.0.1", "localhost"]
    for host in [connect_host, dashboard_origin_host]:
        if host and host not in hosts and host != "0.0.0.0":
            hosts.append(host)
    return hosts


def dashboard_origins(connect_host: str, dashboard_origin_host: str | None) -> list[str]:
    origins: list[str] = []
    for host in origin_hosts(connect_host, dashboard_origin_host):
        for port in [5173, 4173]:
            origin = f"http://{host}:{port}"
            if origin not in origins:
                origins.append(origin)
    return origins


def generate(source_dir: Path, out_dir: Path, bind_host: str, connect_host: str, dashboard_origin_host: str | None) -> None:
    broker = read_json(source_dir / "broker.json")
    worker = read_json(source_dir / "worker.json")
    client = read_json(source_dir / "client.json")
    bridge = read_json(source_dir / "client-bridge.json")

    broker["socketLayer"]["frontendAddr"] = rewrite_tcp_host(broker["socketLayer"]["frontendAddr"], bind_host)
    broker["socketLayer"]["backendAddr"] = rewrite_tcp_host(broker["socketLayer"]["backendAddr"], bind_host)
    broker["infoStorage"]["httpHost"] = bind_host
    for key in ["loggingAddr", "logIngestDefaultAddr"]:
        if key in broker["infoStorage"]:
            broker["infoStorage"][key] = rewrite_tcp_host(broker["infoStorage"][key], bind_host)
    broker["logIngest"]["logIngestAddr"] = rewrite_tcp_host(broker["logIngest"]["logIngestAddr"], bind_host)

    worker["loadBalancerBackendAddr"] = rewrite_tcp_host(worker["loadBalancerBackendAddr"], connect_host)
    if "loadBalancerLoggingAddr" in worker:
        worker["loadBalancerLoggingAddr"] = rewrite_tcp_host(worker["loadBalancerLoggingAddr"], connect_host)
    worker["workerLogging"]["logIngestAddr"] = rewrite_tcp_host(worker["workerLogging"]["logIngestAddr"], connect_host)

    client["loadBalancerFrontendAddr"] = rewrite_tcp_host(client["loadBalancerFrontendAddr"], connect_host)

    bridge["bridgeBindHost"] = bind_host
    bridge["bridgeAllowNoOrigin"] = False
    bridge["bridgeAllowedOrigins"] = dashboard_origins(connect_host, dashboard_origin_host)
    bridge["bridgeClient"]["loadBalancerFrontendAddr"] = rewrite_tcp_host(
        bridge["bridgeClient"]["loadBalancerFrontendAddr"], connect_host
    )

    for name, value in [
        ("broker.json", broker),
        ("worker.json", worker),
        ("client.json", client),
        ("client-bridge.json", bridge),
    ]:
        write_json(out_dir / name, value)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate TaskSchedule public-bind config files")
    parser.add_argument("--source-dir", default="applications/TaskSchedule/config")
    parser.add_argument("--out-dir", default=".tmp/task-schedule-bind-all-config")
    parser.add_argument("--bind-host", default="0.0.0.0")
    parser.add_argument("--connect-host", default="127.0.0.1")
    parser.add_argument("--dashboard-origin-host", default=None)
    args = parser.parse_args()

    generate(
        source_dir=Path(args.source_dir),
        out_dir=Path(args.out_dir),
        bind_host=args.bind_host,
        connect_host=args.connect_host,
        dashboard_origin_host=args.dashboard_origin_host,
    )
    print(f"generated TaskSchedule configs in {args.out_dir}")
