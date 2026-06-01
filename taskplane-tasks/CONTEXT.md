# General — Context

**Last Updated:** 2026-06-01
**Status:** Active
**Next Task ID:** TP-007

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

- [x] **Expose client config reader** — Resolved during TP-004 by exporting `readBrokerConfig`, `readWorkerConfig`, and `readClientConfig` from the `Lotos.Zmq` facade so downstream executables can use the existing config readers.
- [x] **Fix worker status frame decoding** — Resolved during TP-007 by setting the worker DEALER `Z_RoutingId` from `workerId` before backend connect; smoke run `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T032757Z-186410/` shows `/SimpleServer/worker_stats` contains `simpleWorker_1` and backend `WorkerStatus` logs decode cleanly.
- [x] **Complete live client/task submission path** — Resolved during TP-008 by decoding the frontend ROUTER/REQ envelope as routing-id, binary request-id, empty delimiter, and task body; echoing `ClientAck` after successful UUID fill/enqueue; and setting the client REQ routing id from `clientId`. Smoke run `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T040349Z-220141/` passed with `client_exit=0`, an accepted/enqueued ACK, worker registration, and fresh marker proof.
- [ ] **Separate demo suites from regression tests** — `test-conc-executor2`, `test-event-trigger`, `test-logger`, `test-simple-servant`, and `test-zmq-xt` are Cabal test suites but behave as demos/long-running servers; split or reclassify them before making `cabal test all` a CI default (discovered during TP-006).
