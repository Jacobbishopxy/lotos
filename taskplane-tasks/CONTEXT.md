# General — Context

**Last Updated:** 2026-06-02
**Status:** Active
**Next Task ID:** TP-021

---

## Current State

This is the default task area for lotos. Tasks that don't belong
to a specific domain area are created here.

Taskplane is configured and ready for task execution. Use `/orch all` for
parallel batch execution or `/orch <path/to/PROMPT.md>` for a single task.

---

## Key Files

| Category | Path |
|----------|------|
| Tasks | `taskplane-tasks/` |
| Config | `.pi/taskplane-config.json` |

---

## Technical Debt / Future Work

_Items discovered during task execution are logged here by agents._

- [ ] **Complete reliable worker logging hardening** — TP-021 selected the DEALER/ROUTER architecture, TP-022 added the `LogEvent`/`LogBatch`/`LogAck` protocol plus `LogIngestConfig`, TP-023 added broker LogIngest state/query routes, and TP-024 switched workers to a bounded reliable logging DEALER with ACK retry/drop markers, split demo endpoints, structured stdout/stderr/result mapping, and LogIngest backfill for legacy `/info.workerLoggingsMap`. Remaining work is journal restart recovery/retention, applying socket-level HWM, and deciding when to remove or rename the legacy PUB/SUB compatibility surface.
- [ ] **Set package dependency upper bounds** — `cabal check` still warns that `lotos` and TaskSchedule dependency lists omit upper bounds; adding a PVP policy is package-release polish beyond TP-018's docs/examples pass (discovered during TP-018).
- [x] **Recover stale worker tasks** — Resolved during TP-019 by recording broker-side worker status heartbeats, filtering stale workers before scheduler snapshots, and recovering non-succeeded stale-worker tasks through the existing retry-delay or garbage semantics with fixed-clock coverage.
- [x] **Expose client config reader** — Resolved during TP-004 by exporting `readBrokerConfig`, `readWorkerConfig`, and `readClientConfig` from the `Lotos.Zmq` facade so downstream executables can use the existing config readers.
- [x] **Fix worker status frame decoding** — Resolved during TP-007 by setting the worker DEALER `Z_RoutingId` from `workerId` before backend connect; smoke run `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T032757Z-186410/` shows `/SimpleServer/worker_stats` contains `simpleWorker_1` and backend `WorkerStatus` logs decode cleanly.
- [x] **Complete live client/task submission path** — Resolved during TP-008 by decoding the frontend ROUTER/REQ envelope as routing-id, binary request-id, empty delimiter, and task body; echoing `ClientAck` after successful UUID fill/enqueue; and setting the client REQ routing id from `clientId`. Smoke run `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T040349Z-220141/` passed with `client_exit=0`, an accepted/enqueued ACK, worker registration, and fresh marker proof.
- [x] **Make TaskSchedule MVP smoke green** — Resolved during TP-009 by rerunning the final smoke gate after TP-007/TP-008, removing obsolete ACK-blocker exit-2 handling, and documenting evidence. Smoke run `.tmp/task-schedule-smoke/tp009-final-20260601T043107Z-241489/` passed with `status=PASS`, `client_exit=0`, worker `simpleWorker_1` stats, fresh marker proof, and no current-run garbage entry.
- [x] **Separate demo suites from regression tests** — Resolved during TP-010 by reclassifying `test-conc-executor2`, `test-event-trigger`, `test-logger`, `test-simple-servant`, and `test-zmq-xt` as `demo-*` Cabal executables, leaving registered test suites bounded and assertion-based so `cabal test all` is safe as a regression gate.
- [x] **Fix worker task status payload decoding** — Resolved during TP-011 by aligning `WorkerReportTaskStatus.fromZmq` with its serialized frame order `[WorkerTaskStatusT, ack, taskUuid, taskStatus]`; regression coverage now protects retry/failure status payloads and worker task-status forwarding.
- [x] **Harden worker lifecycle/failure semantics** — Resolved during TP-012 by reporting `TaskProcessing` on worker start, resetting worker processing counts after a batch completes, and adding bounded coverage for retry decrement, retry exhaustion to garbage, command success/failure mapping, and timeout exit-code mapping.
- [x] **Wire worker logging into info storage** — Resolved during TP-013 by binding info storage to `infoStorage.loggingAddr` (`5557` in the demo), publishing worker-id topic frames from workers, retaining `workerLoggingsMap` snapshots, and making the smoke path fail unless current-run stdout plus `ExitSuccess` reach `/SimpleServer/info.workerLoggingsMap`.
- [x] **Implement retry delay semantics** — Resolved during TP-015 by storing broker-local retry readiness metadata for failed retries, delaying positive `taskRetryInterval` attempts until eligible, preserving immediate retry for `0`/negative intervals, and covering the behavior with fixed-clock bounded tests.
- [x] **Keep retry-disposition helpers internal** — Resolved during TP-016 by removing `failedTaskDisposition` plus retry-delay helpers (`RetryTask`, `mkRetryTask`, `retryTaskEligible`, `partitionRetryTasks`) from the public `Lotos.Zmq` facade and exposing them only through the narrow `Lotos.Zmq.Internal.Retry` module for bounded broker tests/internal retry implementation work.
- [x] **Prove multi-worker TaskSchedule scheduling smoke** — Resolved during TP-017 by adding `scripts/task-schedule-multi-worker-smoke.sh`, which generates distinct worker/client configs, submits four fresh tasks by default, verifies both `smokeWorker_1` and `smokeWorker_2` in `/worker_stats`, requires per-worker current-run execution evidence plus fresh markers and worker logging, and passed at `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260601T110611Z-1239027/`.
- [x] **Harden TaskSchedule scheduling fairness/backpressure** — Resolved during TP-020 by adding `TaskSchedule:test:test-scheduler` coverage and constraining `SimpleServer` to assign at most one new task to each idle worker snapshot, skip workers with reported processing/waiting work, prefer the lowest CPU/memory load, and return overflow as queued work for a later pass.
- [ ] **Expose worker configured capacity in status payloads** — `WorkerState` reports processing/waiting counts but not the worker's configured `parallelTasksNo`, so TP-020 deliberately used conservative idle-only capacity. Precise multi-slot scheduling should add configured capacity or remaining slots to worker heartbeats/status payloads before changing `SimpleServer` or downstream schedulers.
