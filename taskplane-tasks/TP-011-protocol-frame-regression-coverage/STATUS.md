# TP-011: Protocol Frame Regression Coverage — Status

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
- [x] Current protocol regression tests and Cabal test suites identified

---

### Step 1: Plan frame coverage matrix
**Status:** ✅ Complete

- [x] Protocol directions/frame shapes listed
- [x] Existing vs missing coverage mapped
- [x] Helper extraction needs assessed

---

### Step 2: Implement bounded regression tests
**Status:** ✅ Complete

- [x] Missing frame contract tests added/extended
- [x] Tests are deterministic and bounded
- [x] Cabal metadata updated if needed

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] `cabal build all --enable-tests` passes
- [x] `cabal test all` passes
- [x] Smoke script passes or exact blocker documented

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] README updated if commands changed
- [x] Context debt updated if needed
- [x] Discoveries logged

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | plan | Step 1 | APPROVE | `.reviews/R001-plan-step1.md` |
| R002 | plan | Step 2 | APPROVE | `.reviews/R002-plan-step2.md` |
| R003 | code | Step 2 | APPROVE | `.reviews/R003-code-step2.md` |
| R004 | plan | Step 3 | APPROVE | `.reviews/R004-plan-step3.md` |
| R005 | code | Step 3 | APPROVE | `.reviews/R005-code-step3.md` |

---

## Discoveries

- 2026-06-01: Preflight found existing protocol regression suites `test-zmq-worker-frames` (`lotos/test/ZmqWorkerFrames.hs`) and `test-zmq-client-ack-frames` (`lotos/test/ZmqClientAckFrames.hs`); Cabal currently registers bounded suites `test-conc-executor`, `test-zmq-worker-frames`, and `test-zmq-client-ack-frames`, with long-running demos exposed as `demo-*` executables.
- 2026-06-01: Added missing worker backend protocol coverage for live worker task-status frames, direct `WorkerReportTaskStatus` status payload round-trips (including retry/failure statuses), and ROUTER-to-DEALER scheduled task delivery. The direct round-trip exposed and fixed `WorkerReportTaskStatus.fromZmq`, which previously parsed the message-type frame as an ACK.
- 2026-06-01: Final verification passed with `cabal build all --enable-tests`, `cabal test all`, and `scripts/task-schedule-smoke.sh` (evidence `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T063522Z-435970/`). README coverage wording and `taskplane-tasks/CONTEXT.md` resolved-debt notes were updated for the expanded worker frame regression contract.

---

## Execution Log

| 2026-06-01 06:15 | Task started | Runtime V2 lane-runner execution |
| 2026-06-01 06:15 | Step 0 started | Preflight |
| 2026-06-01 06:15 | Step 0 completed | Required paths and existing suites identified |
| 2026-06-01 06:15 | Step 1 started | Plan frame coverage matrix |
| 2026-06-01 06:16 | Step 1 plan review | R001 APPROVE |
| 2026-06-01 06:16 | Step 1 completed | Coverage matrix approved |
| 2026-06-01 06:16 | Step 2 started | Implement bounded regression tests |
| 2026-06-01 06:16 | Step 2 plan review | R002 APPROVE |
| 2026-06-01 06:20 | Step 2 tests extended | `cabal test lotos:test:test-zmq-worker-frames` passes after fixing `WorkerReportTaskStatus.fromZmq` |
| 2026-06-01 06:21 | Step 2 targeted protocol tests | `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames` passes; new socket tests use `receivesFor ... 1000` bounded waits |
| 2026-06-01 06:21 | Step 2 Cabal check | No `lotos/lotos.cabal` change needed: existing `test-zmq-worker-frames` suite was extended and retained existing dependencies |
| 2026-06-01 06:22 | Step 2 code review | R003 APPROVE |
| 2026-06-01 06:22 | Step 2 completed | Worker frame regression coverage approved |
| 2026-06-01 06:22 | Step 3 started | Testing & Verification |
| 2026-06-01 06:32 | Step 3 plan review | R004 APPROVE |
| 2026-06-01 06:36 | Step 3 build gate | `cabal build all --enable-tests` passed |
| 2026-06-01 06:38 | Step 3 full test gate | `cabal test all` passed (`test-conc-executor`, `test-zmq-worker-frames`, `test-zmq-client-ack-frames`) |
| 2026-06-01 06:35 | Step 3 smoke gate | `scripts/task-schedule-smoke.sh` passed; evidence `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T063522Z-435970/` |
| 2026-06-01 06:41 | Step 3 code review | R005 APPROVE |
| 2026-06-01 06:41 | Step 3 completed | Build, full test, and smoke gates passed |
| 2026-06-01 06:41 | Step 4 started | Documentation & Delivery |
| 2026-06-01 06:42 | Step 4 README check | README command table unchanged; `test-zmq-worker-frames` coverage description updated for expanded frame contracts |
| 2026-06-01 06:42 | Step 4 context debt | Added resolved TP-011 protocol debt entry for `WorkerReportTaskStatus.fromZmq` frame alignment |
| 2026-06-01 06:43 | Step 4 discoveries | Final verification and documentation discoveries logged |
| 2026-06-01 06:43 | Step 4 completed | Documentation and delivery notes complete |
| 2026-06-01 06:43 | Task completed | TP-011 complete |
| 2026-06-01 06:45 | Worker iter 1 | done in 1816s, tools: 100 |
| 2026-06-01 06:45 | Task complete | .DONE created |
---

## Blockers

---

## Notes

### Step 1 Frame Direction Inventory

| Direction | Sender → Receiver | Protected frame shape |
|---|---|---|
| Client request | REQ client → frontend ROUTER | ROUTER receives `[clientRoutingId, reqRequestId, "", taskUuid, taskContent, retry, retryInterval, timeout, taskProp...]`; `RouterFrontendIn` decodes the first three envelope frames before the `Task` body. |
| Client ACK | frontend ROUTER → REQ client | ROUTER sends `[clientRoutingId, reqRequestId, "", ackTimestamp]`; REQ receives only `[ackTimestamp]` and decodes `Ack`. |
| Worker status | DEALER worker → backend ROUTER | ROUTER receives `[workerRoutingId, "WorkerStatusT", ackTimestamp, workerStatus...]`; routing id comes from DEALER `Z_RoutingId`, not the payload. |
| Worker task status | DEALER worker → backend ROUTER | ROUTER receives `[workerRoutingId, "WorkerTaskStatusT", ackTimestamp, taskUuid, taskStatus]`; `TaskStatus` includes retry/failure/success states. |
| Scheduled worker task | backend ROUTER → DEALER worker | ROUTER sends `[workerRoutingId, taskUuid, taskContent, retry, retryInterval, timeout, taskProp...]`; DEALER receives only the `Task` body frames. |
| Retry/failure status payloads | worker task status path | `WorkerReportTaskStatus` carries `TaskRetrying`, `TaskFailed`, and other `TaskStatus` constructors using the same `[type, ack, uuid, status]` payload after the ROUTER routing frame. |

### Step 1 Coverage Map

| Shape | Existing coverage | TP-011 action |
|---|---|---|
| Client request envelope and decode | `ZmqClientAckFrames.clientReqReceivesBrokerAck` asserts the live REQ→ROUTER envelope includes `[clientId, reqId, "", task...]` and decodes `RouterFrontendIn`; malformed request rejection is also covered. | Keep existing coverage; no new case unless implementation reveals a gap. |
| Client ACK envelope and REQ view | `ZmqClientAckFrames.clientReqReceivesBrokerAck` asserts ROUTER `ClientAck` lets REQ receive exactly `[ack]`. | Keep existing coverage. |
| Worker status routing/decode | `ZmqWorkerFrames.workerStatusFramesUseConfiguredDealerRoutingId` asserts DEALER routing id plus `WorkerReportStatus` payload decodes as `RouterBackendIn`. | Keep existing coverage. |
| Worker task status routing/decode | No bounded test currently covers `WorkerReportTaskStatus` over DEALER→ROUTER or all status payload variants. | Add `ZmqWorkerFrames` assertions for live frames and direct retry/failure status payload round-trips. |
| Scheduled worker task delivery | No bounded test currently covers ROUTER→DEALER stripping the worker routing frame and delivering only `Task` body frames. | Add `ZmqWorkerFrames` live ROUTER→DEALER assertion with a deterministic task id. |
| Cabal registration | Existing test suites are already bounded: `test-zmq-worker-frames` and `test-zmq-client-ack-frames`. | Extend existing suite(s); no new suite expected. |

### Step 1 Helper Extraction Assessment

No production helper extraction is needed for the planned coverage: `Lotos.Zmq` already exports the protocol constructors, `ToZmq`/`FromZmq`, `ackFromUTC`, `textToBS`, and `TaskStatus`; tests can build deterministic `Ack`/`TaskID` values locally and assert frame lists directly or through inproc ROUTER/DEALER sockets.
| 2026-06-01 06:21 | Review R001 | plan Step 1: APPROVE |
| 2026-06-01 06:23 | Review R002 | plan Step 2: APPROVE |
| 2026-06-01 06:30 | Review R003 | code Step 2: APPROVE |
| 2026-06-01 06:32 | Review R004 | plan Step 3: APPROVE |
| 2026-06-01 06:41 | Review R005 | code Step 3: APPROVE |
