# TP-012: Worker Lifecycle and Failure Semantics — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-01
**Review Level:** 2
**Review Counter:** 5
**Iteration:** 1
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] TP-011 completed and current tests are green

---

### Step 1: Plan lifecycle/failure coverage
**Status:** ✅ Complete

- [x] Expected lifecycle/failure behavior identified
- [x] Test strategy selected
- [x] Fix-now vs follow-up boundaries defined

---

### Step 2: Implement tests and minimal fixes
**Status:** ✅ Complete

- [x] Bounded tests added
- [x] Minimal production fixes applied if needed
- [x] Happy-path smoke preserved

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] `cabal build all --enable-tests` passes
- [x] `cabal test all` passes
- [x] `scripts/task-schedule-smoke.sh` passes
- [x] Failure-mode evidence captured or blocker documented

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] MVP docs updated if affected
- [x] Context debt updated
- [x] Discoveries logged

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | Plan | Step 1 | APPROVE | `.reviews/R001-plan-step1.md` |
| R002 | Plan | Step 2 | APPROVE | `.reviews/R002-plan-step2.md` |
| R003 | Code | Step 2 | APPROVE | `.reviews/R003-code-step2.md` |
| R004 | Plan | Step 3 | APPROVE | `.reviews/R004-plan-step3.md` |
| R005 | Code | Step 3 | APPROVE | `.reviews/R005-code-step3.md` |

---

## Discoveries

- Worker start callbacks were reporting `TaskInit`, which backend intentionally ignores; changed the TaskSchedule worker to report `TaskProcessing` so lifecycle transitions are observable.
- Worker processing counts stayed non-zero after a batch completed until another batch arrived; reset `wiProcessingTaskNum` to `0` after `processTasks` returns.
- Step 2 targeted verification passed: `cabal test lotos:test:test-zmq-worker-frames TaskSchedule:test:test-worker-lifecycle`; happy-path smoke passed with evidence `.tmp/task-schedule-smoke/tp012-step2-20260601T070442Z-460603/`.
- Step 3 build gate passed: `timeout 300 cabal build all --enable-tests`.
- Step 3 regression gate passed: `timeout 300 cabal test all` (lotos frame/conc suites plus TaskSchedule worker lifecycle suite).
- Step 3 smoke gate passed: `SMOKE_RUN_ID=tp012-step3-20260601T071329Z-471004 timeout 300 scripts/task-schedule-smoke.sh`; evidence `.tmp/task-schedule-smoke/tp012-step3-20260601T071329Z-471004/`.
- Failure-mode evidence captured in bounded suites: `test-zmq-worker-frames` asserts retry `1 -> 0` requeue and retry `0 -> garbage`; `test-worker-lifecycle` asserts success/failure command status mapping and worker `TaskProcessing -> TaskSucceed/TaskFailed` callbacks; `test-conc-executor` asserts timeout returns `ExitFailure 124`.
- Documentation updated: `docs/task-schedule-mvp.md` now states worker lifecycle/failure/retry behavior; `taskplane-tasks/CONTEXT.md` records resolved TP-012 lifecycle hardening and follow-up debt for retry intervals/public helper tightening.

---

## Execution Log

| 2026-06-01 06:48 | Task started | Runtime V2 lane-runner execution |
| 2026-06-01 06:48 | Step 0 started | Preflight |
| 2026-06-01 06:56 | Review R001 | plan Step 1: APPROVE |
| 2026-06-01 06:58 | Review R002 | plan Step 2: APPROVE |
| 2026-06-01 07:09 | Review R003 | code Step 2: APPROVE |
| 2026-06-01 07:11 | Review R004 | plan Step 3: APPROVE |
| 2026-06-01 07:20 | Review R005 | code Step 3: APPROVE |
| 2026-06-01 07:23 | Worker iter 1 | done in 2107s, tools: 116 |
| 2026-06-01 07:23 | Task complete | .DONE created |
---

## Blockers

---

## Notes

### Step 1 lifecycle/failure behavior

- Broker accepts only decodable client tasks, fills a UUID, enqueues the task, and ACKs acceptance/enqueue rather than worker completion.
- Scheduling a task to a worker records it in `workerTasksMap` as `TaskInit`; the worker start callback should report `TaskProcessing`, not another `TaskInit`, because backend `TaskInit` is ignored as a non-transition.
- Worker finish maps `ExitSuccess` to `TaskSucceed`; any `ExitFailure`, including timeout exit `124`, maps to `TaskFailed`.
- Backend `TaskSucceed`/in-flight statuses update the worker task map and notify the task processor; backend `TaskFailed` removes the worker task, decrements `taskRetry` and requeues to `failedTaskQueue` when retries remain, or writes the task to `garbageBin` when retry count is exhausted.
- Task processor pulls both normal and failed queues; unscheduled pulled tasks are re-enqueued to their source queue. `taskRetryInterval` is currently schema-only and does not delay retries.

### Step 1 test strategy

- Extend bounded HUnit coverage rather than adding a long-running failure smoke by default.
- Add core retry/garbage tests around a small pure transition used by `SocketLayer` so retry decrement and exhaustion are protected without starting live ZMQ services.
- Add TaskSchedule worker tests for command-result status mapping and `SimpleWorker.processTasks` status callbacks (start status plus success/failure finish status) using short shell commands.
- Preserve existing frame and happy-path smoke checks as regressions for ROUTER/DEALER payload shape and end-to-end acceptance.

### Step 1 fix-now vs follow-up boundaries

- Fix now: worker start callbacks should report `TaskProcessing`; core retry/garbage transition should be explicit and tested; any small compile/test defects directly revealed by the new bounded tests should be patched.
- Preserve now: command failure/timeout remain collapsed to `TaskFailed` because `TaskStatus` has no reason payload; happy-path ACK/smoke semantics remain unchanged.
- Follow-up debt: `taskRetryInterval` still has no scheduling delay; the info API exposes worker task membership/status tuples but no dedicated failure reason/history endpoint; failure-mode live smoke is optional unless bounded tests expose an integration-only gap.
- Plan review suggestion carried into Step 2: wire TaskSchedule worker coverage into a Cabal test target and include retry `1 -> 0` plus retry `0 -> garbage` boundary cases.
- Step 2 plan review confirmed TaskSchedule cabal metadata may be touched if needed to wire a bounded worker test and advised keeping retry helpers internal unless widening is necessary.
- Step 2 code review approved and noted one non-blocking future cleanup: avoid widening the public `Lotos.Zmq` facade for retry disposition if an internal-test arrangement is introduced later.
- Step 3 plan review approved; use explicit timeouts/cleanup discipline and record exact command outcomes/artifact paths.
- Step 3 code review approved; reviewer reran/confirmed build and test gates and inspected smoke evidence at `.tmp/task-schedule-smoke/tp012-step3-20260601T071329Z-471004/`.
