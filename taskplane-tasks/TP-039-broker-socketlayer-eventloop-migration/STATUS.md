# TP-039: Migrate broker SocketLayer sockets to EventLoop — Status

**Current Step:** Step 5: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-03
**Review Level:** 3
**Review Counter:** 9
**Iteration:** 2
**Size:** L

> **Hydration:** Checkboxes represent meaningful outcomes, not individual code
> changes. Workers expand steps when runtime discoveries warrant it.

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Design broker EventLoop topology
**Status:** ✅ Complete

- [x] Plan-review checkpoint — define endpoint names and mailbox/callback policy for frontend ROUTER, backend ROUTER, TaskProcessor receiver PAIR, and notification sender PAIR.
- [x] Specify how client ACKs and worker task dispatch sends are issued through EventLoop without touching registered sockets directly.
- [x] Define mailbox capacity/failure behavior; task/status traffic must not be silently dropped.
- [x] R001 revision — replace built-in dropping mailboxes with a deterministic no-silent-loss callback handoff policy for critical inbound broker traffic.

---

### Step 2: Implement EventLoop-owned SocketLayer
**Status:** ✅ Complete

- [x] Register SocketLayer sockets with `withEventLoopIn` using explicit context.
- [x] Drain frontend/backend/TaskProcessor mailboxes and invoke extracted handlers from TP-038.
- [x] Send client ACKs, worker tasks, and scheduler notifications through EventLoop command APIs.
- [x] Preserve worker liveness heartbeat updates and retry/garbage semantics.
- [x] R003 revision — split one-frame dispatch from bounded batch draining so the drain limit is enforced and queue preference is not reset recursively.
- [x] R003 revision — replace `tryReadTQueue`/`orElse` fallback with explicit queue-order probing so non-preferred queued traffic is not ignored.
- [x] R004 revision — rotate drain preference across frontend, backend, and TaskProcessor queues so TaskProcessor dispatch frames cannot starve under sustained frontend/backend traffic.

---

### Step 3: Strengthen protocol and scheduler coverage
**Status:** ✅ Complete

- [x] Add or update tests for client ACK after enqueue, worker task dispatch, worker status, task status retry/garbage, and notify path.
- [x] Add mixed-queue broker drain coverage proving TaskProcessor dispatch frames are processed despite queued frontend/backend traffic.
- [x] Verify multipart frame ordering remains unchanged for all public ZMQ protocols.
- [x] Ensure no heavy queue/map mutation occurs on EventLoop callback thread.

---

### Step 4: Testing & Verification
**Status:** ✅ Complete

- [x] Test-review checkpoint — review broker socket ownership and protocol coverage.
- [x] Run broker/client/worker frame tests and scheduler tests.
- [x] Run `cabal build all --enable-tests`.
- [x] Run `scripts/task-schedule-smoke.sh` and `scripts/task-schedule-multi-worker-smoke.sh`.

---

### Step 5: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update `taskplane-tasks/CONTEXT.md` with broker SocketLayer EventLoop migration status and residual risks.
- [x] Update source comments to remove obsolete direct-poll deferral rationale.
- [x] Ensure exactly one final TP commit exists.

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | Plan | Step 1 | REVISE | .reviews/R001-plan-step1.md |
| R002 | Plan | Step 1 | APPROVE | .reviews/R002-plan-step1.md |
| R003 | Code | Step 2 | REVISE | .reviews/R003-code-step2.md |
| R004 | Code | Step 2 | REVISE | .reviews/R004-code-step2.md |
| R005 | Code | Step 2 | APPROVE | .reviews/R005-code-step2.md |
| R006 | Plan | Step 3 | APPROVE | .reviews/R006-plan-step3.md |
| R007 | Code | Step 3 | APPROVE | .reviews/R007-code-step3.md |
| R008 | Plan | Step 4 | APPROVE | .reviews/R008-plan-step4.md |
| R009 | Code | Step 4 | APPROVE | .reviews/R009-code-step4.md |

---

## Notes / Discoveries

### Step 1 broker EventLoop topology plan

- Register all SocketLayer-owned sockets in one `Zmqx.EventLoop.withEventLoopIn` bracket using the `LotosApp` explicit context. Endpoint names are `broker.frontend`, `broker.backend`, `broker.taskprocessor.in`, and `broker.taskprocessor.notify`. `broker.frontend` and `broker.backend` are ROUTER transceivers using `Callback` delivery; `broker.taskprocessor.in` is a TaskProcessor-to-SocketLayer PAIR receiver using `Callback` delivery; `broker.taskprocessor.notify` is a PAIR sender endpoint. EventLoop callbacks do no broker business logic: they only atomically enqueue complete multipart frame sets into SocketLayer-owned STM `TQueue`s, so queue/map/ring-buffer mutation stays on the SocketLayer app thread.
- Client ACKs, worker task dispatch, and scheduler notifications are sent only with `EventLoop.sends` against the registered endpoint names. Business handlers keep their existing send-callback seams, but callbacks call `EventLoop.sends` and surface failures through `zmqUnwrap` so task/status traffic is not reported as successful if the EventLoop is stopped or cannot send.
- Critical inbound broker traffic does not use `Zmqx.EventLoop.Mailbox` because bounded mailboxes drop newest frames silently on overflow. The no-silent-loss handoff is: EventLoop `Callback` receives a complete multipart message, writes it to an unbounded SocketLayer-owned STM `TQueue`, and returns immediately; the SocketLayer loop drains bounded batches from these queues and invokes the TP-038 handlers. This matches the TP-035/TP-037 callback-to-owner-thread pattern, preserves ZMQ backpressure at the EventLoop receive boundary without an additional dropping mailbox, and makes any EventLoop send/recv/callback exception a logged fail-stop transport error instead of silent task/status loss.

### Step 2 review notes

- R003 suggestion: `drainSocketLayerFrames` could return `SocketLayerFrames` directly because its blocking `readTQueue` alternatives never return `Nothing`.
- R004 suggestion: consider deriving the next drain preference from the frame just handled so the blocking read's frontend bias does not reset every batch.

### Step 3 verification notes

- `grep -n "Zmqx.EventLoop.Callback" -A1 -B1 lotos/src/Lotos/Zmq/LBS/SocketLayer.hs` shows all three broker callbacks are `atomically . writeTQueue` handoffs only; queue/map/ring-buffer mutation remains in the SocketLayer loop handlers.
- Targeted protocol tests passed: `cabal test lotos:test:test-zmq-client-ack-frames lotos:test:test-zmq-worker-frames --test-options='--hide-successes'`.

### Step 4 verification notes

- Test-review checkpoint passed as R008.
- Broker/client/worker frame and scheduler tests passed: `cabal test lotos:test:test-zmq-client-ack-frames lotos:test:test-zmq-worker-frames lotos:test:test-zmq-worker-wake --test-options='--hide-successes'`.
- Full build gate passed: `cabal build all --enable-tests`.
- Smoke gates passed: `scripts/task-schedule-smoke.sh` (evidence `.tmp/task-schedule-smoke/task-schedule-smoke-20260603T140806Z-3537282`) and `scripts/task-schedule-multi-worker-smoke.sh` (evidence `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260603T140854Z-3537281`).

- None yet.

| 2026-06-03 13:29 | Task started | Runtime V2 lane-runner execution |
| 2026-06-03 13:29 | Step 0 started | Preflight |
| 2026-06-03 13:32 | Review R001 | plan Step 1: REVISE |
| 2026-06-03 13:34 | Review R002 | plan Step 1: APPROVE |

| 2026-06-03 13:35 | Worker iter 1 | done in 381s, tools: 36 |
| 2026-06-03 13:35 | Step 2 started | Implement EventLoop-owned SocketLayer |
| 2026-06-03 13:44 | Review R003 | code Step 2: REVISE |
| 2026-06-03 13:49 | Review R004 | code Step 2: REVISE |
| 2026-06-03 13:52 | Review R005 | code Step 2: APPROVE |
| 2026-06-03 13:54 | Review R006 | plan Step 3: APPROVE |
| 2026-06-03 14:05 | Review R007 | code Step 3: APPROVE |
| 2026-06-03 14:06 | Review R008 | plan Step 4: APPROVE |
| 2026-06-03 14:13 | Review R009 | code Step 4: APPROVE |

| 2026-06-03 14:17 | Worker iter 2 | done in 2489s, tools: 174 |
| 2026-06-03 14:17 | Task complete | .DONE created |