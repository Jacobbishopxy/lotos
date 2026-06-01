# TP-015: Implement Retry Delay Semantics — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-01
**Review Level:** 2
**Review Counter:** 6
**Iteration:** 1
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Current retry behavior and tests are understood

---

### Step 1: Design retry-delay model
**Status:** ✅ Complete

- [x] Eligibility semantics defined
- [x] Delayed retry metadata location chosen
- [x] Bounded tests designed

---

### Step 2: Implement retry delay behavior
**Status:** ✅ Complete

- [x] Positive retry intervals delay eligibility
- [x] Zero/negative retry intervals remain immediate
- [x] Retry exhaustion still moves to garbage
- [x] Helper/API exposure minimized or documented

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] `cabal build all --enable-tests` passes
- [x] `cabal test all` passes
- [x] `scripts/task-schedule-smoke.sh` passes
- [x] Bounded tests prove delayed/immediate retry behavior

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] MVP docs updated
- [x] README updated if needed
- [x] Context debt updated
- [x] Discoveries logged

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| 1 | Plan | Step 1 | APPROVE | `.reviews/R001-plan-step1.md` |
| 2 | Code | Step 1 | APPROVE | `.reviews/R002-code-step1.md` |
| 3 | Plan | Step 2 | APPROVE | `.reviews/R003-plan-step2.md` |
| 4 | Code | Step 2 | APPROVE | `.reviews/R004-code-step2.md` |
| 5 | Plan | Step 3 | APPROVE | `.reviews/R005-plan-step3.md` |
| 6 | Code | Step 3 | APPROVE | `.reviews/R006-code-step3.md` |

---

## Discoveries

| 2026-06-01 | Current retry path: `handleFailedTask` calls `failedTaskDisposition`; remaining retries are enqueued immediately to `failedTaskQueue`, exhausted retries go to `garbageBin`. `TaskProcessor` currently dequeues all failed tasks alongside new tasks with no time eligibility check. Existing `test-zmq-worker-frames` covers retry decrement and exhaustion only. |
| 2026-06-01 | Retry delay helpers (`RetryTask`, `mkRetryTask`, `retryTaskEligible`, `partitionRetryTasks`) are currently exported through `Lotos.Zmq` because `TaskSchedulerData` exposes the failed-queue type and bounded tests import the public facade; fold this into the existing TP-016 API-tightening debt if the facade is narrowed. |
| 2026-06-01 | Retry readiness is enforced as not-before eligibility in the task processor's existing trigger loop, not as a precise per-task timer; docs now call out this scheduling caveat. |

---

## Execution Log

| 2026-06-01 09:17 | Task started | Runtime V2 lane-runner execution |
| 2026-06-01 09:17 | Step 0 started | Preflight |
| 2026-06-01 | Step 0 evidence | Verified required paths, created missing `.reviews/`, inspected retry path/tests, and ran `cabal test lotos:test:test-zmq-worker-frames` (PASS, 6 cases). |
| 2026-06-01 | Step 1 evidence | Recorded retry eligibility semantics, metadata envelope choice, and bounded test design; plan and code reviews returned APPROVE. |
| 2026-06-01 | Step 2 positive-delay evidence | Added `RetryTask` readiness metadata, scheduler partitioning, and bounded positive-interval tests; targeted `cabal test lotos:test:test-zmq-worker-frames` passed 9 cases. |
| 2026-06-01 | Step 2 review | Step 2 code review returned APPROVE for retry-delay implementation. |
| 2026-06-01 | Step 3 build evidence | `cabal build all --enable-tests` completed successfully. |
| 2026-06-01 | Step 3 test evidence | `cabal test all` passed (`test-zmq-worker-frames`, `test-zmq-client-ack-frames`, `test-worker-lifecycle`, and `test-conc-executor`). |
| 2026-06-01 | Step 3 smoke evidence | `scripts/task-schedule-smoke.sh` passed; evidence dir `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T094502Z-746207`. |
| 2026-06-01 | Step 3 bounded retry evidence | `test-zmq-worker-frames` includes fixed-clock assertions for positive delayed retry, zero/negative immediate retry, and partitioning delayed retries out of scheduling batches; passed in targeted and full runs. |
| 2026-06-01 | Step 3 review | Step 3 code review returned APPROVE for verification evidence. |
| 2026-06-01 | Step 4 MVP docs | `docs/task-schedule-mvp.md` now documents `taskRetryInterval` delay semantics, broker-local metadata, TP-015 evidence, and the not-before (not exact deadline) scheduling caveat. |
| 2026-06-01 | Step 4 README | `README.md` now describes public retry-delay behavior in architecture, app-extension, regression-test, and protocol-note sections. |
| 2026-06-01 | Step 4 context | `taskplane-tasks/CONTEXT.md` marks retry-delay semantics resolved and folds TP-015 public helper exposure into the existing API-tightening debt. |
| 2026-06-01 | Step 4 discoveries | STATUS discoveries capture the original retry path, helper/API exposure caveat, and not-before scheduling caveat. |
| 2026-06-01 09:54 | Worker iter 1 | done in 2246s, tools: 119 |
| 2026-06-01 09:54 | Task complete | .DONE created |
---

## Blockers

---

## Notes

### Step 1 proposed design (pending plan review)
- Eligibility: `taskRetryInterval <= 0` keeps existing immediate retry behavior; positive intervals create a not-before timestamp when the failed retry is enqueued, and the task is not passed to `scheduleTasks` until `now >= readyAt`. `failedTaskDisposition` still decrements `taskRetry` first; `taskRetry <= 0` still goes directly to garbage.
- Metadata: keep `Task` JSON/ZMQ frames unchanged. Store retry readiness in an internal failed-queue envelope (`RetryTask`/equivalent) that pairs the decremented task with `Maybe UTCTime`, so info storage can still expose plain queued tasks and wire compatibility is preserved.
- Tests: add bounded pure tests with fixed `UTCTime` values for positive delayed, zero/negative immediate, and due retry behavior; keep existing retry-decrement/exhaustion tests and run targeted `test-zmq-worker-frames` after implementation.
| 2026-06-01 09:25 | Review R001 | plan Step 1: APPROVE |
| 2026-06-01 09:27 | Review R002 | code Step 1: APPROVE |
| 2026-06-01 09:30 | Review R003 | plan Step 2: APPROVE |
| 2026-06-01 09:40 | Review R004 | code Step 2: APPROVE |
| 2026-06-01 09:42 | Review R005 | plan Step 3: APPROVE |
| 2026-06-01 09:48 | Review R006 | code Step 3: APPROVE |
