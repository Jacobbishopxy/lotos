# Task: TP-034 - Convert EventLoop usage to explicit context

**Created:** 2026-06-03
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** This narrows EventLoop context ownership while touching worker logging and tests. The behavior should remain stable but lifecycle correctness is important.
**Score:** 5/8 — Blast radius: 1, Pattern novelty: 2, Security: 0, Reversibility: 2

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-034-eventloop-explicit-context/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Switch current EventLoop usage from active-global-context lookup to explicit-context `withEventLoopIn`, aligning worker logging with the new monadic context model before adding more EventLoop-owned sockets.

## Dependencies

- **Task:** TP-033 (core socket operations use explicit monadic context)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/Monad.hs` — confirm current `Zmqx.Monad` API details.
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/EventLoop.hs` — confirm current EventLoop ownership and mailbox APIs when this task touches EventLoop.

## Environment

- **Workspace:** `/home/xiey/Code/lotos`
- **Services required:** Worker reliable logging transport; no live services required until smoke verification.

## File Scope

- `lotos/src/Lotos/Zmq/LBW/LogTransport.hs`
- `lotos/src/Lotos/Logger.hs`
- `lotos/src/Lotos/Zmq/Util.hs`
- `lotos/test/ZmqWorkerLogTransport.hs`
- `lotos/test/ZmqLogIngest.hs`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Design explicit EventLoop context access

- [ ] Plan-review checkpoint — decide whether EventLoop context is obtained via `askContext`, `LotosEnv`, or a helper wrapper.
- [ ] Ensure EventLoop sockets are opened in the same explicit context that `withEventLoopIn` receives.
- [ ] Document constraints for future EventLoop migrations.

### Step 2: Update worker log EventLoop

- [ ] Replace `Zmqx.EventLoop.withEventLoop` with `withEventLoopIn` in worker log transport.
- [ ] Preserve mailbox ACK draining, retry, in-flight, and drop accounting semantics.
- [ ] Ensure forked logging loop receives the same explicit context as the worker service.

### Step 3: Testing & Verification

- [ ] Code review checkpoint — review context handoff and socket ownership boundaries.
- [ ] Run `cabal test lotos:test:test-zmq-worker-log-transport lotos:test:test-zmq-log-ingest lotos:test:test-zmq-log-protocol-config`.
- [ ] Run `cabal build all --enable-tests`.
- [ ] Run `scripts/task-schedule-smoke.sh`.

### Step 4: Documentation & Delivery

- [ ] Update `taskplane-tasks/CONTEXT.md` with explicit EventLoop context status.
- [ ] Record any EventLoop helper conventions in STATUS.md.
- [ ] Ensure exactly one final TP commit exists.

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md` — note EventLoop now uses explicit context.

**Check If Affected:**
- `docs/logging-redesign.md` — update if logging lifecycle wording changes.

## Completion Criteria

- [ ] All steps complete
- [ ] All tests passing with evidence recorded in STATUS.md
- [ ] Protocol frame ordering preserved or explicitly covered by regression tests
- [ ] Documentation updated
- [ ] Exactly one final TP commit exists

## Git Commit Convention

Commits happen at **step boundaries** (not after every checkbox). The final integrated history must squash this task into exactly one TP commit.

Recommended final commit subject:

`TP-034: Convert EventLoop usage to explicit context`

## Do NOT

- Expand scope into unrelated feature work; log follow-ups in `taskplane-tasks/CONTEXT.md`
- Claim exactly-once logging delivery
- Change ZMQ multipart frame ordering without explicit regression coverage
- Couple worker logging backpressure to task/status backend traffic
- Commit a final history with more than one commit for this TP

---

## Amendments (Added During Execution)

<!-- Workers add amendments here if issues discovered during execution. -->
