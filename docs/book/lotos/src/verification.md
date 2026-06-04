# Verification Guide

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
```

## Regression tests

Run targeted suites when changing a narrow area. Examples:

```bash
cabal test lotos:test:test-conc-executor
cabal test lotos:test:test-zmq-client-ack-frames
cabal test TaskSchedule:test:test-scheduler
```

Use frame tests whenever a `ToZmq`/`FromZmq` instance changes.

## Runtime smokes

Use the bounded TaskSchedule smoke helpers for end-to-end proof:

```bash
scripts/task-schedule-smoke.sh
scripts/task-schedule-multi-worker-smoke.sh
```

Expected evidence includes client ACKs, worker stats, current-run task side effects, `/logs/worker/<workerId>` result events, clean `/logs/stats`, and no current-run garbage entry.

## Failure triage

- ACK timeout: verify frontend/backend addresses and REQ/ROUTER frame preservation.
- Missing worker stats: verify worker backend address, worker routing id, and heartbeat interval versus stale timeout.
- Missing logs: verify LogIngest endpoint alignment and journal isolation for the run.
- Capacity surprises: verify `processingTaskNum`, `waitingTaskNum`, and `taskCapacity` in worker status payloads.
