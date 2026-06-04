# Task: TP-041 - Review client REQ path under monad/EventLoop architecture

**Created:** 2026-06-03
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** This affects the public client request path but is smaller than broker/worker migrations. It may add timeout behavior or explicitly keep direct monadic REQ.
**Score:** 4/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 2

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-041-client-req-monad-eventloop-review/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Review and finalize the client `REQ` path after monad and EventLoop migrations, deciding whether it should remain direct monadic request/ACK or move to EventLoop for bounded request/ACK timeout behavior.

## Dependencies

- **Task:** TP-040 (TaskProcessor migration/adaptation)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/Monad.hs` — confirm current `Zmqx.Monad` API details.
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/EventLoop.hs` — confirm current EventLoop ownership and mailbox APIs when this task touches EventLoop.

## Environment

- **Workspace:** `/home/xiey/Code/lotos`
- **Services required:** Client API and TaskSchedule client executable.

## File Scope

- `lotos/src/Lotos/Zmq/LBC.hs`
- `lotos/src/Lotos/Zmq.hs`
- `applications/TaskSchedule/app/TaskScheduleClient.hs`
- `lotos/test/ZmqClientAckFrames.hs`
- `scripts/task-schedule-smoke.sh`
- `README.md`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Evaluate client REQ architecture

- [ ] Plan-review checkpoint — compare direct monadic REQ with EventLoop transceiver for request/ACK traffic.
- [ ] Decide timeout/cancellation behavior and whether it belongs in public client API.
- [ ] Preserve client routing-id and ACK frame semantics.

### Step 2: Implement selected client path

- [ ] If keeping direct: ensure the client path consistently uses monad context and add bounded receive behavior if appropriate.
- [ ] If migrating: register REQ with EventLoop and route request/ACK through command/mailbox APIs.
- [ ] Update TaskSchedule client executable and public facade as needed.

### Step 3: Testing & Verification

- [ ] Code review checkpoint — review public client API compatibility and frame ordering.
- [ ] Run client ACK frame tests.
- [ ] Run `cabal build all --enable-tests`.
- [ ] Run single-worker smoke to prove live client submission still succeeds.

### Step 4: Documentation & Delivery

- [ ] Update README client usage if public behavior changes.
- [ ] Update `taskplane-tasks/CONTEXT.md` with final client path decision.
- [ ] Ensure exactly one final TP commit exists.

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md` — record client path final decision.

**Check If Affected:**
- `README.md` — update if client API/timeout behavior changes.

## Completion Criteria

- [ ] All steps complete
- [ ] All tests passing with evidence recorded in STATUS.md
- [ ] Protocol frame ordering preserved or explicitly covered by regression tests
- [ ] Documentation updated
- [ ] Exactly one final TP commit exists

## Git Commit Convention

Commits happen at **step boundaries** (not after every checkbox). The final integrated history must squash this task into exactly one TP commit.

Recommended final commit subject:

`TP-041: Review client REQ path under monad/EventLoop architecture`

## Do NOT

- Expand scope into unrelated feature work; log follow-ups in `taskplane-tasks/CONTEXT.md`
- Claim exactly-once logging delivery
- Change ZMQ multipart frame ordering without explicit regression coverage
- Couple worker logging backpressure to task/status backend traffic
- Commit a final history with more than one commit for this TP

---

## Amendments (Added During Execution)

<!-- Workers add amendments here if issues discovered during execution. -->
