# TP-038: Extract broker SocketLayer handlers for EventLoop migration — Status

**Current Step:** Step 5: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-03
**Review Level:** 2
**Review Counter:** 6
**Iteration:** 1
**Size:** M

> **Hydration:** Checkboxes represent meaningful outcomes, not individual code
> changes. Workers expand steps when runtime discoveries warrant it.

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Identify pure handler boundaries
**Status:** ✅ Complete

- [x] Plan-review checkpoint — map frontend client request, backend worker status, worker task-status, load-balancer dispatch, and notify handling.
- [x] Choose helper signatures that accept decoded protocol values and explicit send callbacks where needed.
- [x] Confirm no frame ordering changes are needed.

---

### Step 2: Extract behavior-preserving helpers
**Status:** ✅ Complete

- [x] Extract frontend task enqueue/client ACK logic from direct socket receive mechanics.
- [x] Extract worker status/task-status mutation and retry/garbage logic from backend socket mechanics.
- [x] Extract load-balancer worker-task dispatch and workerTasksMap update logic.

---

### Step 3: Preserve direct poll loop behavior
**Status:** ✅ Complete

- [x] Keep the current direct poll loop for this TP.
- [x] Update comments to describe the extraction as EventLoop preparation, not migration.
- [x] Verify no additional ReaderT or heavyweight abstraction is introduced in hot path unnecessarily.

---

### Step 4: Testing & Verification
**Status:** ✅ Complete

- [x] Code review checkpoint — compare old/new handler behavior.
- [x] Run client ACK and worker frame tests.
- [x] Run scheduler/fairness tests if broker notification behavior changed.
- [x] Run `cabal build all --enable-tests`.

---

### Step 5: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update `taskplane-tasks/CONTEXT.md` with SocketLayer extraction status.
- [x] Record any uncovered handler seams in STATUS.md.
- [x] Ensure exactly one final TP commit exists.

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| 1 | Plan | 1 | APPROVE | — |
| 2 | Plan | 2 | APPROVE | — |
| 3 | Code | 2 | APPROVE | — |
| 4 | Plan | 3 | APPROVE | — |
| 5 | Code | 3 | APPROVE | — |
| 6 | Code | 4 | APPROVE | — |

---

## Notes / Discoveries

- Step 1 handler boundary map:
  - Frontend client request: keep `handleFrontend` as readiness/socket receive wrapper; extract decoded `ClientRequest clientID clientReqID task` handling into an enqueue-and-ACK helper that fills the UUID, enqueues to `taskQueue`, creates `Ack`, and sends `ClientAck` through an explicit callback.
  - Backend worker status: keep `handleWorkerMessage` as receive/decode wrapper; keep decoded `WorkerStatus` mutation in a helper that logs, inserts `workerStatusMap`, and records `workerAliveMap` only when `WorkerStatusT` is present.
  - Backend worker task-status: route decoded `WorkerTaskStatus` to task-status helpers; retain retry/garbage disposition, worker task map mutation, and load-balancer notify behavior after both failed and non-failed task statuses.
  - Load-balancer dispatch: keep `handleLoadBalancerMessage` as PAIR receive/decode wrapper; extract decoded `WorkerTask` handling into a helper that sends to the backend ROUTER first and then appends `(uuid, task, TaskInit)` to `workerTasksMap`.
  - Notify handling: keep `notifyLoadBalancer` as the only send path for scheduler notifications and pass it as an explicit callback where task-status helpers need it.
- Step 1 chosen helper signatures:
  - `handleClientRequest :: (FromZmq t) => TSQueue (Task t) -> (RouterFrontendOut -> LotosApp ()) -> RoutingID -> ByteString -> Task t -> LotosApp ()`.
  - `dispatchWorkerTask :: (ToZmq t) => TSWorkerTasksMap (TaskID, Task t, TaskStatus) -> (RouterBackendOut t -> LotosApp ()) -> RouterBackendOut t -> LotosApp ()`.
  - `handleWorkerStatusUpdate :: TSWorkerStatusMap w -> TSWorkerAliveMap -> Int -> RoutingID -> WorkerMsgType -> Ack -> w -> LotosApp ()`.
  - `TaskContext` should carry `tcNotifyLoadBalancer :: LotosApp ()` instead of a raw `Zmqx.Pair`, so task-status business logic depends on explicit notify behavior rather than socket mechanics.
- Step 1 frame-order confirmation: the extraction will keep using existing `toZmq`/`fromZmq` instances at socket boundaries (`ClientAck`, `RouterBackendOut`/`WorkerTask`, `RouterBackendIn`), so no multipart frame shapes or ordering need to change.
- Step 3 direct poll verification: `layerLoop` still calls `ZmqxM.poll pollItems`, then `handleFrontend`, then `handleBackend`, then recurses; sockets remain opened/bound in `runSocketLayer` and touched by the same SocketLayer thread.
- Step 3 abstraction verification: grep found no ReaderT/runReader/ask/newtype abstraction in `SocketLayer.hs` beyond comments and the existing lightweight `TaskContext` record; `cabal build lotos` passed after the extraction.
- Step 4 targeted frame verification: `cabal test lotos:test:test-zmq-client-ack-frames lotos:test:test-zmq-worker-frames` passed (client ACK: 2 cases, worker frames: 20 cases).
- Step 4 scheduler verification: notification send behavior was preserved through an explicit callback and `cabal test TaskSchedule:test:test-scheduler` passed (4 cases).
- Step 4 build verification: `cabal build all --enable-tests` passed.
- Step 5 uncovered handler seams: no additional broker handler seams were left uncovered for this TP; socket ownership, mailbox sizing, and EventLoop callbacks remain intentionally out of scope for a future migration task.

| 2026-06-03 13:06 | Task started | Runtime V2 lane-runner execution |
| 2026-06-03 13:06 | Step 0 started | Preflight |
| 2026-06-03 13:10 | Review R001 | plan Step 1: APPROVE |
| 2026-06-03 13:11 | Review R002 | plan Step 2: APPROVE |
| 2026-06-03 13:17 | Review R003 | code Step 2: APPROVE |
| 2026-06-03 13:18 | Review R004 | plan Step 3: APPROVE |
| 2026-06-03 13:21 | Review R005 | code Step 3: APPROVE |
| 2026-06-03 13:24 | Review R006 | code Step 4: APPROVE |

| 2026-06-03 13:28 | Worker iter 1 | done in 1317s, tools: 105 |
| 2026-06-03 13:28 | Task complete | .DONE created |