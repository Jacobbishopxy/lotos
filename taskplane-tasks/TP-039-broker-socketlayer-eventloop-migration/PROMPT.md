# Task: TP-039 - Migrate broker SocketLayer sockets to EventLoop

**Created:** 2026-06-03
**Size:** L

## Review Level: 3 (Full)

**Assessment:** This is the highest-risk migration because it changes ownership for frontend client, backend worker, and TaskProcessor broker traffic. Full review and smoke verification are required.
**Score:** 7/8 — Blast radius: 2, Pattern novelty: 2, Security: 0, Reversibility: 3

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-039-broker-socketlayer-eventloop-migration/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Migrate broker `LBS.SocketLayer` frontend ROUTER, backend ROUTER, and TaskProcessor PAIR traffic to explicit-context EventLoop ownership while preserving client ACKs, worker dispatch/status frames, retry/garbage handling, liveness, and scheduler notifications.

## Dependencies

- **Task:** TP-038 (SocketLayer handler extraction)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/Monad.hs` — confirm current `Zmqx.Monad` API details.
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/EventLoop.hs` — confirm current EventLoop ownership and mailbox APIs when this task touches EventLoop.

## Environment

- **Workspace:** `/home/xiey/Code/lotos`
- **Services required:** Broker SocketLayer with TaskSchedule smoke services.

## File Scope

- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs`
- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs`
- `lotos/test/ZmqClientAckFrames.hs`
- `lotos/test/ZmqWorkerFrames.hs`
- `lotos/test/ZmqWorkerWake.hs`
- `applications/TaskSchedule/src/Server.hs`
- `scripts/task-schedule-smoke.sh`
- `scripts/task-schedule-multi-worker-smoke.sh`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Design broker EventLoop topology

- [ ] Plan-review checkpoint — define endpoint names and mailbox/callback policy for frontend ROUTER, backend ROUTER, TaskProcessor receiver PAIR, and notification sender PAIR.
- [ ] Specify how client ACKs and worker task dispatch sends are issued through EventLoop without touching registered sockets directly.
- [ ] Define mailbox capacity/failure behavior; task/status traffic must not be silently dropped.

### Step 2: Implement EventLoop-owned SocketLayer

- [ ] Register SocketLayer sockets with `withEventLoopIn` using explicit context.
- [ ] Drain frontend/backend/TaskProcessor mailboxes and invoke extracted handlers from TP-038.
- [ ] Send client ACKs, worker tasks, and scheduler notifications through EventLoop command APIs.
- [ ] Preserve worker liveness heartbeat updates and retry/garbage semantics.

### Step 3: Strengthen protocol and scheduler coverage

- [ ] Add or update tests for client ACK after enqueue, worker task dispatch, worker status, task status retry/garbage, and notify path.
- [ ] Verify multipart frame ordering remains unchanged for all public ZMQ protocols.
- [ ] Ensure no heavy queue/map mutation occurs on EventLoop callback thread.

### Step 4: Testing & Verification

- [ ] Test-review checkpoint — review broker socket ownership and protocol coverage.
- [ ] Run broker/client/worker frame tests and scheduler tests.
- [ ] Run `cabal build all --enable-tests`.
- [ ] Run `scripts/task-schedule-smoke.sh` and `scripts/task-schedule-multi-worker-smoke.sh`.

### Step 5: Documentation & Delivery

- [ ] Update `taskplane-tasks/CONTEXT.md` with broker SocketLayer EventLoop migration status and residual risks.
- [ ] Update source comments to remove obsolete direct-poll deferral rationale.
- [ ] Ensure exactly one final TP commit exists.

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md` — record broker SocketLayer EventLoop migration result.

**Check If Affected:**
- `docs/task-schedule-mvp.md` — update if smoke/runtime behavior changed.

## Completion Criteria

- [ ] All steps complete
- [ ] All tests passing with evidence recorded in STATUS.md
- [ ] Protocol frame ordering preserved or explicitly covered by regression tests
- [ ] Documentation updated
- [ ] Exactly one final TP commit exists

## Git Commit Convention

Commits happen at **step boundaries** (not after every checkbox). The final integrated history must squash this task into exactly one TP commit.

Recommended final commit subject:

`TP-039: Migrate broker SocketLayer sockets to EventLoop`

## Do NOT

- Expand scope into unrelated feature work; log follow-ups in `taskplane-tasks/CONTEXT.md`
- Claim exactly-once logging delivery
- Change ZMQ multipart frame ordering without explicit regression coverage
- Couple worker logging backpressure to task/status backend traffic
- Commit a final history with more than one commit for this TP

---

## Amendments (Added During Execution)

<!-- Workers add amendments here if issues discovered during execution. -->
