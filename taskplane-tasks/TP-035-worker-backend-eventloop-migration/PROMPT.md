# Task: TP-035 - Migrate worker backend transport to EventLoop

**Created:** 2026-06-03
**Size:** L

## Review Level: 3 (Full)

**Assessment:** This changes worker task receive and status-report transport ownership. It touches runtime ordering and lifecycle behavior, requiring full review and smoke proof.
**Score:** 6/8 — Blast radius: 2, Pattern novelty: 2, Security: 0, Reversibility: 2

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-035-worker-backend-eventloop-migration/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Migrate `LBW.socketLoop` from direct polling to EventLoop-owned worker backend DEALER plus internal PAIR handling while keeping task enqueue, wake-on-enqueue, heartbeat, and task-status frame semantics intact.

## Dependencies

- **Task:** TP-034 (EventLoop uses explicit context)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/Monad.hs` — confirm current `Zmqx.Monad` API details.
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/EventLoop.hs` — confirm current EventLoop ownership and mailbox APIs when this task touches EventLoop.

## Environment

- **Workspace:** `/home/xiey/Code/lotos`
- **Services required:** Worker service runtime; smoke scripts start local demo services.

## File Scope

- `lotos/src/Lotos/Zmq/LBW.hs`
- `lotos/src/Lotos/Zmq/Internal/WorkerRuntime.hs`
- `lotos/test/ZmqWorkerFrames.hs`
- `lotos/test/ZmqWorkerWake.hs`
- `applications/TaskSchedule/src/Worker.hs`
- `scripts/task-schedule-smoke.sh`
- `scripts/task-schedule-multi-worker-smoke.sh`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Design worker backend EventLoop ownership

- [ ] Plan-review checkpoint — define endpoint names, mailbox capacities, heartbeat timing, and internal PAIR handling.
- [ ] Keep EventLoop callbacks lightweight; prefer mailbox drain on the worker socket-loop thread.
- [ ] Specify how status reports are sent through EventLoop without directly touching registered sockets.

### Step 2: Implement EventLoop-backed worker backend loop

- [ ] Register worker backend DEALER as a transceiver and internal PAIR as receiver/transceiver as needed.
- [ ] Forward task-status frames from internal callbacks/API to backend DEALER through EventLoop commands.
- [ ] Receive task frames via mailbox, enqueue to the worker task queue, and notify the wake signal in the same ordering as before.
- [ ] Preserve periodic worker status reporting cadence.

### Step 3: Protect ordering and lifecycle behavior

- [ ] Add or update tests for task receive ordering, task-status frame forwarding, heartbeat send behavior, and wake-on-enqueue after EventLoop migration.
- [ ] Ensure logging EventLoop remains independent from backend EventLoop so logging backpressure cannot block task/status traffic.
- [ ] Handle stopped-loop errors without silent task loss.

### Step 4: Testing & Verification

- [ ] Test-review checkpoint — review worker task/status traffic correctness and lifecycle coverage.
- [ ] Run `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-worker-wake lotos:test:test-zmq-worker-log-transport`.
- [ ] Run relevant TaskSchedule worker lifecycle/scheduler tests.
- [ ] Run `cabal build all --enable-tests`.
- [ ] Run `scripts/task-schedule-smoke.sh` and `scripts/task-schedule-multi-worker-smoke.sh`.

### Step 5: Documentation & Delivery

- [ ] Update `taskplane-tasks/CONTEXT.md` with worker backend EventLoop migration status and remaining risks.
- [ ] Update source comments to describe EventLoop ownership boundaries.
- [ ] Ensure exactly one final TP commit exists.

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md` — record worker backend EventLoop migration result.

**Check If Affected:**
- `docs/task-schedule-mvp.md` — update only if smoke behavior or operational notes change.

## Completion Criteria

- [ ] All steps complete
- [ ] All tests passing with evidence recorded in STATUS.md
- [ ] Protocol frame ordering preserved or explicitly covered by regression tests
- [ ] Documentation updated
- [ ] Exactly one final TP commit exists

## Git Commit Convention

Commits happen at **step boundaries** (not after every checkbox). The final integrated history must squash this task into exactly one TP commit.

Recommended final commit subject:

`TP-035: Migrate worker backend transport to EventLoop`

## Do NOT

- Expand scope into unrelated feature work; log follow-ups in `taskplane-tasks/CONTEXT.md`
- Claim exactly-once logging delivery
- Change ZMQ multipart frame ordering without explicit regression coverage
- Couple worker logging backpressure to task/status backend traffic
- Commit a final history with more than one commit for this TP

---

## Amendments (Added During Execution)

<!-- Workers add amendments here if issues discovered during execution. -->
