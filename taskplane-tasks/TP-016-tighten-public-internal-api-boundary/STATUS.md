# TP-016: Tighten Public/Internal API Boundary — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-01
**Review Level:** 2
**Review Counter:** 6
**Iteration:** 3
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] TP-015 completion status and helper/API changes understood

---

### Step 1: Audit public exports
**Status:** ✅ Complete

- [x] Public exports classified
- [x] Test internal-access strategy decided
- [x] Affected docs identified

---

### Step 2: Apply boundary cleanup
**Status:** ✅ Complete

- [x] Test-only helpers removed/relocated from public facade where safe
- [x] Tests updated to narrower/internal imports
- [x] Intended extension points preserved

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] `cabal build all --enable-tests` passes
- [x] `cabal test all` passes
- [x] `scripts/task-schedule-smoke.sh` passes
- [x] Public docs match exported API

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] README updated if needed
- [x] Context debt updated
- [x] Discoveries logged

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| 1 | Plan | Step 1 | APPROVE | `.reviews/R001-plan-step1.md` |
| 2 | Code | Step 1 | UNAVAILABLE | reviewer produced no output |
| 3 | Plan | Step 2 | APPROVE | `.reviews/R003-plan-step2.md` |
| 4 | Code | Step 2 | APPROVE | `.reviews/R004-code-step2.md` |
| 5 | Plan | Step 3 | APPROVE | `.reviews/R005-plan-step3.md` |
| 6 | Code | Step 3 | APPROVE | `.reviews/R006-code-step3.md` |

---

## Discoveries

| 2026-06-01 | Public facade boundary | `Lotos.Zmq` should remain the supported user-facing facade; retry-disposition/readiness helpers are implementation/test support and now live behind `Lotos.Zmq.Internal.Retry` for bounded broker regression coverage. |
| 2026-06-01 | Documentation scope | README API guidance needed narrowing to the facade/internal retry boundary; `docs/task-schedule-mvp.md` did not require changes because retry behavior semantics were unchanged. |

---

## Execution Log

| 2026-06-01 09:57 | Task started | Runtime V2 lane-runner execution |
| 2026-06-01 09:57 | Step 0 started | Preflight |
| 2026-06-01 | Step 0 evidence | Verified required paths, created missing `.reviews/`, confirmed TP-015 status is complete, inspected retry helper exports (`failedTaskDisposition`, `RetryTask`, `mkRetryTask`, `retryTaskEligible`, `partitionRetryTasks`), and ran `cabal test lotos:test:test-zmq-worker-frames` (PASS, 9 cases). |
| 2026-06-01 | Step 1 evidence | Classified the `Lotos.Zmq` facade, chose a narrow `Lotos.Zmq.Internal.Retry` import path for bounded helper tests, identified README and context-debt updates, and received plan review APPROVE. |
| 2026-06-01 | Review R002 | code Step 1: UNAVAILABLE (reviewer exited without output); proceeding cautiously because no source boundary changes have been applied yet. |
| 2026-06-01 | Step 2 facade cleanup | Replaced the wholesale `module Lotos.Zmq.Adt` facade re-export with an explicit public export list and added `Lotos.Zmq.Internal.Retry` as the narrow retry-helper access module. |
| 2026-06-01 | Step 2 test import cleanup | Updated `test-zmq-worker-frames` to import retry helpers from `Lotos.Zmq.Internal.Retry`; `cabal test lotos:test:test-zmq-worker-frames` passed (9 cases). |
| 2026-06-01 | Step 2 extension-point check | `cabal build TaskSchedule:exe:ts-server TaskSchedule:exe:ts-worker TaskSchedule:exe:ts-client` passed, confirming the documented app extension points still compile through `Lotos.Zmq`. |
| 2026-06-01 | Step 3 build evidence | `cabal build all --enable-tests` passed. |
| 2026-06-01 | Step 3 test evidence | `cabal test all` passed (`test-zmq-worker-frames`, `test-zmq-client-ack-frames`, `test-worker-lifecycle`, and `test-conc-executor`). |
| 2026-06-01 | Step 3 smoke evidence | `scripts/task-schedule-smoke.sh` passed; evidence preserved at `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T102210Z-975556`. |
| 2026-06-01 | Step 3 docs evidence | README public-module guidance now points users at `Lotos.Zmq`, stops advertising lower-level `Lotos.Zmq.*` implementation modules, and grep confirmed no README/MVP references to removed retry helpers. |
| 2026-06-01 | Step 4 README evidence | README now lists `Lotos.Zmq` as the supported ZMQ facade and explicitly scopes `Lotos.Zmq.Internal.Retry` to bounded broker regression/implementation work. |
| 2026-06-01 | Step 4 context evidence | Marked the retry-disposition helper debt resolved in `taskplane-tasks/CONTEXT.md` with the new `Lotos.Zmq.Internal.Retry` boundary. |
| 2026-06-01 | Step 4 discoveries evidence | Logged the facade/internal retry boundary and documentation-scope findings in the Discoveries section. |
| 2026-06-01 10:21 | Worker iter 1 | done in 1455s, tools: 98 |
| 2026-06-01 10:32 | Worker iter 2 | done in 660s, tools: 38 |
| 2026-06-01 10:34 | Worker iter 3 | done in 88s, tools: 11 |
| 2026-06-01 10:34 | Task complete | .DONE created |
---

## Blockers

---

## Notes

### Step 1 audit: public export classification
- Extension points / entry points to preserve in `Lotos.Zmq`: `LoadBalancerAlgo`, `ScheduledResult`, `runLBS`, `TaskAcceptorAPI`, `TaskAcceptor`, `WorkerInfo`, `StatusReporterAPI`, `StatusReporter`, `WorkerService`, `mkWorkerService`, `runWorkerService`, `getAcceptor`, `getReporter`, `listTasksInQueue`, `ClientService`, `mkClientService`, `sendTaskRequest`.
- Config/readers to preserve: `BrokerServiceConfig`, `readBrokerConfig`, `WorkerServiceConfig`, `readWorkerConfig`, `ClientServiceConfig`, `readClientConfig`, `TaskSchedulerConfig`, `SocketLayerConfig`, `TaskProcessorConfig`, `InfoStorageConfig`.
- Protocol/user ADTs and classes to preserve: `RoutingID`, `TaskID`, `TSWorkerStatusMap`, `ToZmq`, `FromZmq`, `Task`, `defaultTask`, `fillTaskID`, `fillTaskID'`, `unsafeGetTaskID`, `Ack`/ACK helpers, router/worker protocol wrappers, `TaskStatus`, `WorkerMsgType`, `Notify`, `WorkerLogging`, worker task map helpers, event triggers, and `Lotos.Zmq.Util` conversions/context helpers.
- Internal/test-only retry surface to remove from the facade: `FailedTaskDisposition`, `failedTaskDisposition`, `RetryTask`, `mkRetryTask`, `retryTaskEligible`, and `partitionRetryTasks`. These are broker retry-disposition/readiness helpers and are only used directly by bounded tests/internal scheduler code.
- Test/internal access strategy: keep the helper definitions in `Lotos.Zmq.Adt` for existing internal scheduler code, stop re-exporting them from `Lotos.Zmq`, and add a narrow `Lotos.Zmq.Internal.Retry` module that re-exports only the retry-disposition/readiness helpers for bounded tests. `lotos/test/ZmqWorkerFrames.hs` will import this internal module while continuing to import normal protocol/extension names from `Lotos.Zmq`.
- Affected docs: update `README.md` if its public module guidance still advertises internal implementation modules as user-facing API; update `taskplane-tasks/CONTEXT.md` to resolve/refine the retry-helper debt. `docs/task-schedule-mvp.md` does not need a behavior change unless export cleanup alters public retry semantics (it should not).
| 2026-06-01 10:05 | Review R001 | plan Step 1: APPROVE |
| 2026-06-01 10:10 | Review R003 | plan Step 2: APPROVE |
| 2026-06-01 10:16 | Review R004 | code Step 2: APPROVE |
| 2026-06-01 10:18 | Review R005 | plan Step 3: APPROVE |
| 2026-06-01 10:30 | Review R006 | code Step 3: APPROVE |
