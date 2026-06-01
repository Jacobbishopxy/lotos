# TP-019: Worker Liveness and Disconnect Recovery — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-01
**Review Level:** 2
**Review Counter:** 4
**Iteration:** 2
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Current liveness TODOs and worker/task state maps are understood

---

### Step 1: Design liveness and recovery semantics
**Status:** ✅ Complete

- [x] Staleness detection model defined
- [x] Stale worker removal semantics defined
- [x] In-flight task recovery semantics defined
- [x] Bounded tests/smoke evidence defined

Design notes:
- Staleness detection: record broker-side `AliveSensor` metadata (`asLastSeen`, timeout seconds) whenever a worker status heartbeat is accepted; use a fixed-clock helper to classify entries stale when `now >= asLastSeen + timeout`. Add optional `taskProcessor.workerStaleTimeoutSec` with a conservative default so existing broker JSON continues to parse, and set demo configs to a timeout above the worker heartbeat interval.
- Stale worker removal: before each scheduler pass snapshots `workerStatusMap`, recover stale IDs from the broker liveness map, then remove those IDs from the liveness map, `workerStatusMap`, and `workerTasksMap` so `scheduleTasks` never receives stale workers and info snapshots stop advertising dead workers/tasks.
- In-flight task recovery: treat stale-worker tasks in `TaskInit`, `TaskPending`, `TaskProcessing`, `TaskRetrying`, or lingering `TaskFailed` as broker-observed failures and pass them through `failedTaskDisposition` plus `mkRetryTask now`; retryable tasks keep existing retry-delay semantics and exhausted tasks go to garbage. `TaskSucceed` entries are dropped with the stale worker rather than re-executed.
- Evidence plan: add fixed-clock HUnit coverage to `test-zmq-worker-frames` for `aliveSensorStale` and stale-worker task recovery (retry decrement/readiness, garbage when exhausted, no retry for succeeded entries), then run `cabal build all --enable-tests`, `cabal test all`, and both TaskSchedule smoke scripts.

---

### Step 2: Implement recovery logic
**Status:** ✅ Complete

- [x] Stale worker recovery helper(s) added
- [x] Stale workers removed from status/task maps appropriately
- [x] In-flight tasks recovered with retry/garbage semantics
- [x] Healthy smoke behavior preserved

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] `cabal build all --enable-tests` passes
- [x] `cabal test all` passes
- [x] Single-worker smoke passes
- [x] Multi-worker smoke passes
- [x] Bounded stale-worker recovery tests pass

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] README/docs updated if needed
- [x] Context debt updated
- [x] Discoveries logged

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | Plan | 2 | APPROVE | `.reviews/R001-plan-step2.md` |
| R002 | Code | 2 | APPROVE | `.reviews/R002-code-step2.md` |
| R003 | Plan | 3 | APPROVE | `.reviews/R003-plan-step3.md` |
| R004 | Code | 3 | APPROVE | `.reviews/R004-code-step3.md` |

---

## Discoveries

- Preflight: `AliveSensor` was an unused TODO-only data type; the broker scheduled from `workerStatusMap` without timestamps/liveness filtering, and `workerTasksMap` held per-worker in-flight `(TaskID, Task, TaskStatus)` entries that were only retried/garbaged when a worker reported `TaskFailed`.
- Implementation: TP-019 now records broker-side worker status heartbeats in `TSWorkerAliveMap`, filters stale workers before scheduler snapshots, removes stale workers from liveness/status/task maps, and recovers non-succeeded in-flight tasks through existing retry-delay or garbage semantics without changing ZeroMQ frame order.
- Verification: `cabal build all --enable-tests`, `cabal test all`, `cabal test lotos:test:test-zmq-worker-frames`, single-worker smoke `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T140959Z-1455662/`, and multi-worker smoke `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260601T141128Z-1457758/` passed.

---

## Execution Log

| 2026-06-01 13:35 | Task started | Runtime V2 lane-runner execution |
| 2026-06-01 13:35 | Step 0 started | Preflight |
| 2026-06-01 13:42 | Worker iter 1 | done in 395s, tools: 43 |
| 2026-06-01 13:42 | Step 2 started | Implement recovery logic |
| 2026-06-01 14:26 | Worker iter 2 | done in 2656s, tools: 131 |
| 2026-06-01 14:26 | Task complete | .DONE created |
---

## Blockers

---

## Notes
| 2026-06-01 13:46 | Review R001 | plan Step 2: APPROVE |
| 2026-06-01 14:06 | Review R002 | code Step 2: APPROVE |
| 2026-06-01 14:08 | Review R003 | plan Step 3: APPROVE |
| 2026-06-01 14:21 | Review R004 | code Step 3: APPROVE |
