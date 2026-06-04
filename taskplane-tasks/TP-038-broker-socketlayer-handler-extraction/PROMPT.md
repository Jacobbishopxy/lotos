# Task: TP-038 - Extract broker SocketLayer handlers for EventLoop migration

**Created:** 2026-06-03
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** This is a preparatory refactor with multiple broker paths but no intended protocol changes. Plan and code review should protect behavior.
**Score:** 4/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 1

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-038-broker-socketlayer-handler-extraction/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Prepare `LBS.SocketLayer` for EventLoop ownership by separating socket receive/send mechanics from frontend, backend, retry, garbage, and scheduler-notification business logic without changing behavior.

## Dependencies

- **Task:** TP-037 (LogIngest EventLoop migration)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/Monad.hs` — confirm current `Zmqx.Monad` API details.
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/EventLoop.hs` — confirm current EventLoop ownership and mailbox APIs when this task touches EventLoop.

## Environment

- **Workspace:** `/home/xiey/Code/lotos`
- **Services required:** Broker SocketLayer; no live services required until verification.

## File Scope

- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs`
- `lotos/test/ZmqClientAckFrames.hs`
- `lotos/test/ZmqWorkerFrames.hs`
- `applications/TaskSchedule/src/Server.hs`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Identify pure handler boundaries

- [ ] Plan-review checkpoint — map frontend client request, backend worker status, worker task-status, load-balancer dispatch, and notify handling.
- [ ] Choose helper signatures that accept decoded protocol values and explicit send callbacks where needed.
- [ ] Confirm no frame ordering changes are needed.

### Step 2: Extract behavior-preserving helpers

- [ ] Extract frontend task enqueue/client ACK logic from direct socket receive mechanics.
- [ ] Extract worker status/task-status mutation and retry/garbage logic from backend socket mechanics.
- [ ] Extract load-balancer worker-task dispatch and workerTasksMap update logic.

### Step 3: Preserve direct poll loop behavior

- [ ] Keep the current direct poll loop for this TP.
- [ ] Update comments to describe the extraction as EventLoop preparation, not migration.
- [ ] Verify no additional ReaderT or heavyweight abstraction is introduced in hot path unnecessarily.

### Step 4: Testing & Verification

- [ ] Code review checkpoint — compare old/new handler behavior.
- [ ] Run client ACK and worker frame tests.
- [ ] Run scheduler/fairness tests if broker notification behavior changed.
- [ ] Run `cabal build all --enable-tests`.

### Step 5: Documentation & Delivery

- [ ] Update `taskplane-tasks/CONTEXT.md` with SocketLayer extraction status.
- [ ] Record any uncovered handler seams in STATUS.md.
- [ ] Ensure exactly one final TP commit exists.

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md` — note broker SocketLayer preparation status.

**Check If Affected:**
- `docs/task-schedule-mvp.md` — update only if broker behavior notes change.

## Completion Criteria

- [ ] All steps complete
- [ ] All tests passing with evidence recorded in STATUS.md
- [ ] Protocol frame ordering preserved or explicitly covered by regression tests
- [ ] Documentation updated
- [ ] Exactly one final TP commit exists

## Git Commit Convention

Commits happen at **step boundaries** (not after every checkbox). The final integrated history must squash this task into exactly one TP commit.

Recommended final commit subject:

`TP-038: Extract broker SocketLayer handlers for EventLoop migration`

## Do NOT

- Expand scope into unrelated feature work; log follow-ups in `taskplane-tasks/CONTEXT.md`
- Claim exactly-once logging delivery
- Change ZMQ multipart frame ordering without explicit regression coverage
- Couple worker logging backpressure to task/status backend traffic
- Commit a final history with more than one commit for this TP

---

## Amendments (Added During Execution)

<!-- Workers add amendments here if issues discovered during execution. -->
