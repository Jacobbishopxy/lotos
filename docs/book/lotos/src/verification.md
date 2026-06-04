# Verification Guide

## Routine CI/local profile

Use the Makefile CI profile for the standard contributor gate:

```bash
make ci-check
```

`ci-check` is intentionally CI-safe. It runs:

1. `make ci-build` — `cabal build all --enable-tests`, compiling libraries, executables, registered test suites, and demo executables without launching demos or servers.
2. `make ci-test` — the explicit bounded regression target list in `CI_TEST_TARGETS`.
3. `make ci-docs` — `mdbook build docs/book/lotos` through the `book-build` target.

A repository-hosted workflow is not required for the profile itself; this repo currently has no `.github/workflows` directory, so TP-049 keeps CI wiring dependency-free and documents the Makefile gate for contributors and future workflow integration.

## Documentation checks

For this book:

```bash
make book-build
make book-serve
```

`book-build` runs `mdbook build` against `MDBOOK_DIR`. `book-serve` runs `mdbook serve` with configurable host and port. Do not commit the generated `book/` output directory after local builds.

## Haskell build checks

For source changes, prefer the narrowest command that proves the touched component, then widen when the task asks for it:

```bash
cabal build lotos
cabal build TaskSchedule:exe:ts-server
cabal build TaskSchedule:exe:ts-worker
cabal build all --enable-tests
make ci-build
```

## Regression tests

`make ci-test` runs the bounded regression list explicitly instead of launching demo/server executables. The default target list is:

```bash
lotos:test:test-conc-executor
lotos:test:test-zmq-worker-frames
lotos:test:test-zmq-client-ack-frames
lotos:test:test-zmq-worker-wake
lotos:test:test-zmq-capacity-reservations
lotos:test:test-zmq-log-protocol-config
lotos:test:test-zmq-log-ingest
lotos:test:test-zmq-worker-log-transport
TaskSchedule:test:test-worker-lifecycle
TaskSchedule:test:test-scheduler
```

Run targeted suites when changing a narrow area. Examples:

```bash
cabal test lotos:test:test-conc-executor
cabal test lotos:test:test-zmq-client-ack-frames
cabal test TaskSchedule:test:test-scheduler
```

Use frame tests whenever a `ToZmq`/`FromZmq` instance changes. Override `CI_TEST_TARGETS` for a narrower local pass when needed:

```bash
make ci-test CI_TEST_TARGETS="lotos:test:test-zmq-worker-frames TaskSchedule:test:test-scheduler"
```

## Runtime smokes

Runtime smoke helpers remain explicit opt-in and are not part of `make ci-check`:

```bash
make smoke-single
make smoke-multi
# or directly:
scripts/task-schedule-smoke.sh
scripts/task-schedule-multi-worker-smoke.sh
```

Expected evidence includes client ACKs, worker stats, current-run task side effects, `/logs/worker/<workerId>` stdout/result events, clean LogIngest-only `/logs/stats`, broker `/info.runtimeQueueStats`, and no current-run garbage entry. The multi-worker smoke also checks generated worker capacity and a reservation-safe in-flight dispatch snapshot so queued bursts do not exceed configured worker slots while heartbeats catch up.

## Failure triage

Use the [Runtime Failure Runbook](runtime-failures.md) for operator recovery steps after stuck workers, LogIngest backlog, broker handoff queue growth, stale heartbeat recovery, reservation underutilization, or smoke failures. The bullets below are quick pointers for identifying the failing verification surface.

- CI build failure: rerun the failing component from `cabal build all --enable-tests` with `-v` if Cabal output does not identify the component.
- CI regression failure: rerun the printed `cabal test <target>` command; `make ci-test` echoes each target before executing it.
- Docs failure: run `make book-build` and inspect the mdBook source path reported by mdBook.
- ACK timeout: verify frontend/backend addresses and REQ/ROUTER frame preservation.
- Missing worker stats: verify worker backend address, worker routing id, and heartbeat interval versus stale timeout.
- Missing logs: verify LogIngest endpoint alignment and journal isolation for the run; `/logs/stats` reports LogIngest drop/reject/sequence accounting, not task/status queue depth.
- Missing runtime stats: inspect `/SimpleServer/info` for `runtimeQueueStats` entries with `currentDepth`, `highWaterDepth`, `totalEnqueued`, and `totalDrained` fields.
- Capacity surprises: verify `processingTaskNum`, `waitingTaskNum`, `taskCapacity`, and broker reservations in worker status/worker-task snapshots.
