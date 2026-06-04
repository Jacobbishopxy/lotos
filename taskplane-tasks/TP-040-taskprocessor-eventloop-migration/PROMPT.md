# Task: TP-040 - Migrate TaskProcessor internal transport to EventLoop

**Created:** 2026-06-03
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** This changes internal PAIR communication and scheduler trigger timing but should be constrained to the broker load-balancer loop. Plan and code review are needed.
**Score:** 5/8 — Blast radius: 1, Pattern novelty: 2, Security: 0, Reversibility: 2

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-040-taskprocessor-eventloop-migration/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Migrate or adapt `LBS.TaskProcessor` internal PAIR communication to explicit-context EventLoop ownership so the broker runtime has consistent socket ownership after SocketLayer migration.

## Dependencies

- **Task:** TP-039 (broker SocketLayer EventLoop migration)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/Monad.hs` — confirm current `Zmqx.Monad` API details.
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/EventLoop.hs` — confirm current EventLoop ownership and mailbox APIs when this task touches EventLoop.

## Environment

- **Workspace:** `/home/xiey/Code/lotos`
- **Services required:** Broker TaskProcessor and scheduler tests.

## File Scope

- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs`
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs`
- `applications/TaskSchedule/src/Server.hs`
- `applications/TaskSchedule/src/Adt.hs`
- `lotos/test/*`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Evaluate TaskProcessor EventLoop shape

- [ ] Plan-review checkpoint — decide whether TaskProcessor PAIR sockets should be sender/receiver/transceiver endpoints or whether SocketLayer migration already centralized ownership enough.
- [ ] Map scheduler trigger timing and timeout behavior to EventLoop mailbox/timer logic.
- [ ] Define success criteria and explicit no-op fallback if migration is not beneficial.

### Step 2: Implement migration or documented adaptation

- [ ] If migrating: register TaskProcessor PAIR sockets through EventLoop and use command/mailbox APIs for notify receive and worker-task sends.
- [ ] If not migrating fully: adapt TaskProcessor to the new explicit context/socket ownership conventions and document the remaining direct path.
- [ ] Preserve scheduler output ordering and retry-ready task dispatch behavior.

### Step 3: Testing & Verification

- [ ] Code review checkpoint — review scheduler trigger, notify, and dispatch semantics.
- [ ] Run scheduler/fairness/backpressure tests.
- [ ] Run worker liveness/retry tests affected by dispatch timing.
- [ ] Run `cabal build all --enable-tests` and smoke scripts if runtime dispatch changed.

### Step 4: Documentation & Delivery

- [ ] Update `taskplane-tasks/CONTEXT.md` with TaskProcessor EventLoop status.
- [ ] Record any remaining direct socket ownership in STATUS.md.
- [ ] Ensure exactly one final TP commit exists.

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md` — record TaskProcessor migration/adaptation result.

**Check If Affected:**
- `docs/build-your-own-scheduler.md` — update if scheduler extension behavior changes.

## Completion Criteria

- [ ] All steps complete
- [ ] All tests passing with evidence recorded in STATUS.md
- [ ] Protocol frame ordering preserved or explicitly covered by regression tests
- [ ] Documentation updated
- [ ] Exactly one final TP commit exists

## Git Commit Convention

Commits happen at **step boundaries** (not after every checkbox). The final integrated history must squash this task into exactly one TP commit.

Recommended final commit subject:

`TP-040: Migrate TaskProcessor internal transport to EventLoop`

## Do NOT

- Expand scope into unrelated feature work; log follow-ups in `taskplane-tasks/CONTEXT.md`
- Claim exactly-once logging delivery
- Change ZMQ multipart frame ordering without explicit regression coverage
- Couple worker logging backpressure to task/status backend traffic
- Commit a final history with more than one commit for this TP

---

## Amendments (Added During Execution)

<!-- Workers add amendments here if issues discovered during execution. -->
