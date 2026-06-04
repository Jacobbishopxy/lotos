# Operations Runbook

## Build and test

Use Cabal from the repository root:

```bash
cabal build all
cabal build all --enable-tests
cabal test lotos:test:test-conc-executor
```

Avoid `cabal test all` as a default long-running check only if a task specifically warns about demo suites. In the current workspace, registered Cabal tests are intended to be bounded regression suites; server-style demos are executables and should be run intentionally, often under `timeout`.

## Run the TaskSchedule smoke helpers

```bash
cabal build all --enable-tests
scripts/task-schedule-smoke.sh
scripts/task-schedule-multi-worker-smoke.sh
```

The helpers generate run-local configs/evidence under `.tmp/`, start only the services they track, probe the HTTP info/log endpoints, verify worker marker files and current-run log events, and clean up tracked process groups.

## HTTP probes

With default TaskSchedule config, useful endpoints include:

```text
/SimpleServer/info
/SimpleServer/tasks
/SimpleServer/garbage
/SimpleServer/worker_tasks
/SimpleServer/worker_stats
/SimpleServer/logs/recent
/SimpleServer/logs/worker/<workerId>
/SimpleServer/logs/task/<taskUuid>
/SimpleServer/logs/stats
```

Use `curl --noproxy '*'` for loopback probes in proxy-enabled environments.

## Overload indicators

`/SimpleServer/info` includes `runtimeQueueStats`, a small list of no-drop handoff queue snapshots. Each entry reports:

- `name` — the broker queue being observed.
- `currentDepth` — enqueue/dequeue-tracked depth at snapshot time.
- `highWaterDepth` — highest observed depth since process start.
- `totalEnqueued` / `totalDrained` — monotonic counters for diagnosis.
- `warningThreshold` — depth that starts bounded WARN logging.

These metrics are observability only: task/status handoff queues stay intentionally unbounded and non-dropping. Treat rising `currentDepth` or repeatedly increasing `highWaterDepth` as overload evidence, then inspect worker capacity, scheduler throughput, and downstream task execution time. `/logs/stats` remains LogIngest-specific rejected/drop accounting; do not interpret it as task/status queue loss.

## Logging operations

Reliable logs are persisted through the broker LogIngest journal and exposed through `/logs/*`. Generated smoke runs should use isolated journal paths or remove stale generated state when proving current-run evidence, because stable worker ids can otherwise make old accepted sequences appear as duplicates.

## mdBook operations

The documentation book is intentionally optional tooling. Use the Makefile targets from the repository root:

```bash
make book-build
make book-serve
```

Override location and serving address as needed:

```bash
make book-serve MDBOOK_DIR=docs/book/lotos MDBOOK_HOST=0.0.0.0 MDBOOK_PORT=3003
```
