# TP-007: Fix Worker Status Frame Decoding — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-01
**Review Level:** 2
**Review Counter:** 3
**Iteration:** 1
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Current worker status decode failure confirmed from logs/smoke evidence

---

### Step 1: Diagnose frame shape mismatch
**Status:** ✅ Complete

- [x] Worker status frame flow traced
- [x] Actual frames compared with decoders
- [x] Minimal invariant-preserving fix identified

---

### Step 2: Implement decode/handling fix
**Status:** ✅ Complete

- [x] Affected frame code patched
- [x] Frame ordering invariants preserved
- [x] Targeted regression coverage added/updated if practical

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] `cabal build all` passes
- [x] `cabal build all --enable-tests` passes
- [x] `cabal test lotos:test:test-conc-executor` passes
- [x] Runtime worker stats check passes or exact blocker documented

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] MVP docs updated
- [x] Context debt updated
- [x] Discoveries logged

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | plan | 1 | APPROVE | `.reviews/R001-plan-step1.md` |
| R002 | code | 2 | APPROVE | `.reviews/R002-code-step2.md` |
| R003 | code | 3 | APPROVE | `.reviews/R003-code-step3.md` |

---

## Discoveries

| 2026-06-01 | Preflight evidence | `docs/task-schedule-mvp.md` and `taskplane-tasks/CONTEXT.md` record TP-005 smoke evidence: server HTTP readiness passed, `/SimpleServer/worker_stats` stayed empty, and backend logged `ZmqParsing "Text decode error: Cannot decode byte '\\xe4'"` while handling worker status frames. |
| 2026-06-01 | Worker status flow | `LBW.socketLoop` sends `toZmq (WorkerReportStatus ack workerStatus)` on a DEALER connected to the backend ROUTER; `SocketLayer.handleWorkerMessage` receives backend ROUTER frames and decodes them as `RouterBackendIn w` before inserting `WorkerStatus` into `workerStatusMap`. |
| 2026-06-01 | Frame mismatch | `WorkerReportStatus` payload frames are `[WorkerStatusT, ack, worker-state...]`; the backend ROUTER prepends its routing-id frame, so `RouterBackendIn` decodes `[routing-id, WorkerStatusT, ack, worker-state...]`. `Zmqx.name "workerDealer"` is only a debug name, not a ROUTER identity, so the routing-id may be generated binary and fail `textFromBS` before the message type is decoded. |
| 2026-06-01 | Planned fix | Set `Z_RoutingId` on the worker DEALER from `WorkerServiceConfig.workerId` before connecting to the backend ROUTER. This changes only the transport identity frame, leaving `WorkerReportStatus`, `WorkerReportTaskStatus`, and `RouterBackendIn` payload ordering unchanged. |
| 2026-06-01 | Implementation | `LBW.runWorkerService` now sets `Z_RoutingId` from `workerId` before connecting the DEALER to the backend ROUTER. |
| 2026-06-01 | Invariant check | Diff only changes the worker DEALER routing-id option; `WorkerReportStatus`, `WorkerReportTaskStatus`, `RouterBackendIn`, and `RouterBackendOut` frame constructors/decoders remain unchanged. |
| 2026-06-01 | Regression coverage | Added `lotos:test:test-zmq-worker-frames`, an inproc ROUTER/DEALER regression that sets `Z_RoutingId`, receives the worker status frames, and decodes them through `RouterBackendIn ()`. |
| 2026-06-01 | Runtime worker stats | Smoke run `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T032757Z-186410/` registered `simpleWorker_1`; `worker-ready-worker_stats.json` contains a `WorkerStat` entry and server logs show repeated `handleBackend -> WorkerStatus: "simpleWorker_1"`. The smoke still exits `1` after registration because `ts-client` reports `no ACK received`, marker proof is missing, and server logs `ZmqParsing "Invalid UUID format"` while handling the submitted task path. |
| 2026-06-01 | Delivery notes | README run instructions are unchanged; MVP docs and context debt now carry the updated worker-registration evidence and remaining post-registration blocker. |

---

## Execution Log

| 2026-06-01 03:08 | Task started | Runtime V2 lane-runner execution |
| 2026-06-01 03:08 | Step 0 started | Preflight |
| 2026-06-01 | Step 0 completed | Required files verified and TP-005 smoke/log failure evidence confirmed. |
| 2026-06-01 | Step 1 started | Diagnose frame shape mismatch. |
| 2026-06-01 | Step 1 plan review | R001 APPROVE. |
| 2026-06-01 | Step 1 completed | Minimal worker DEALER routing-id fix identified. |
| 2026-06-01 | Step 2 started | Implement decode/handling fix. |
| 2026-06-01 | Step 2 targeted test | `cabal test lotos:test:test-zmq-worker-frames` passed. |
| 2026-06-01 | Step 2 code review | R002 APPROVE. |
| 2026-06-01 | Step 2 completed | Worker DEALER routing-id fix and regression accepted. |
| 2026-06-01 | Step 3 started | Testing & Verification. |
| 2026-06-01 | Verification | `cabal build all` passed. |
| 2026-06-01 | Verification | `cabal build all --enable-tests` passed. |
| 2026-06-01 | Verification | `cabal test lotos:test:test-conc-executor` passed. |
| 2026-06-01 | Verification | Runtime worker stats check passed in smoke run `task-schedule-smoke-20260601T032757Z-186410`; remaining smoke failure moved past worker registration. |
| 2026-06-01 | Step 3 code review | R003 APPROVE. |
| 2026-06-01 | Step 3 completed | Build/test/runtime worker stats evidence accepted. |
| 2026-06-01 | Step 4 started | Documentation & Delivery. |
| 2026-06-01 | Documentation | `docs/task-schedule-mvp.md` updated with TP-007 worker registration evidence and the new post-registration blocker. |
| 2026-06-01 | Documentation | `taskplane-tasks/CONTEXT.md` marked worker status decoding resolved and refined the remaining live client/task submission debt. |
| 2026-06-01 | Documentation | Discoveries table updated with final delivery notes. |
| 2026-06-01 | Step 4 completed | Documentation and delivery notes updated. |
| 2026-06-01 | Task completed | TP-007 complete. |
| 2026-06-01 03:36 | Worker iter 1 | done in 1688s, tools: 138 |
| 2026-06-01 03:36 | Task complete | .DONE created |
---

## Blockers

---

## Notes
| 2026-06-01 03:16 | Review R001 | plan Step 1: APPROVE |
| 2026-06-01 03:24 | Review R002 | code Step 2: APPROVE |
| 2026-06-01 03:32 | Review R003 | code Step 3: APPROVE |
