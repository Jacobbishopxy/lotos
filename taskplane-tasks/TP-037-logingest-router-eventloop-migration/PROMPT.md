# Task: TP-037 - Migrate LogIngest ROUTER to EventLoop

**Created:** 2026-06-03
**Size:** L

## Review Level: 3 (Full)

**Assessment:** This changes broker logging ingestion socket ownership and ACK timing while touching durability semantics. Full review is warranted.
**Score:** 6/8 — Blast radius: 2, Pattern novelty: 2, Security: 0, Reversibility: 2

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-037-logingest-router-eventloop-migration/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Migrate broker `LogIngest` ROUTER receive/ACK handling to explicit-context EventLoop ownership while preserving at-least-once ingestion, idempotent sequence handling, journal durability, retention, and ACK protocol frames.

## Dependencies

- **Task:** TP-034 (explicit EventLoop context)
- **Task:** TP-036 (worker EventLoop lifecycle hardening)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/Monad.hs` — confirm current `Zmqx.Monad` API details.
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/EventLoop.hs` — confirm current EventLoop ownership and mailbox APIs when this task touches EventLoop.

## Environment

- **Workspace:** `/home/xiey/Code/lotos`
- **Services required:** Broker LogIngest service; smoke scripts exercise live worker log flow.

## File Scope

- `lotos/src/Lotos/Zmq/LBS/LogIngest.hs`
- `lotos/test/ZmqLogIngest.hs`
- `lotos/test/ZmqWorkerLogTransport.hs`
- `docs/logging-redesign.md`
- `scripts/task-schedule-smoke.sh`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Design LogIngest EventLoop ownership

- [ ] Plan-review checkpoint — decide ROUTER transceiver endpoint, mailbox capacity, ACK send path, and how ingestion work is kept off EventLoop callbacks.
- [ ] Preserve worker routing-id frame handling and `LogBatch`/`LogAck` frame ordering.
- [ ] Decide how malformed frames and journal errors are accounted under mailbox dispatch.

### Step 2: Implement EventLoop-backed ingestion

- [ ] Register LogIngest ROUTER as an EventLoop transceiver with explicit context.
- [ ] Drain mailbox frames in the ingestion loop, apply existing dedupe/journal/retention logic, and send ACKs via EventLoop.
- [ ] Preserve existing HTTP query/storage behavior.

### Step 3: Validate durability and backpressure semantics

- [ ] Ensure at-least-once semantics are still documented; do not claim exactly-once.
- [ ] Verify mailbox-full handling cannot silently hide accepted batches without observable accounting.
- [ ] Keep worker retry/delayed ACK behavior compatible.

### Step 4: Testing & Verification

- [ ] Test-review checkpoint — review durability, malformed-frame, ACK, and retention coverage.
- [ ] Run `cabal test lotos:test:test-zmq-log-ingest lotos:test:test-zmq-worker-log-transport lotos:test:test-zmq-log-protocol-config`.
- [ ] Run `cabal build all --enable-tests`.
- [ ] Run single and multi-worker smoke scripts.

### Step 5: Documentation & Delivery

- [ ] Update `docs/logging-redesign.md` with LogIngest EventLoop ownership if user-facing enough.
- [ ] Update `taskplane-tasks/CONTEXT.md` with migration status and risks.
- [ ] Ensure exactly one final TP commit exists.

## Documentation Requirements

**Must Update:**
- `docs/logging-redesign.md` — note LogIngest socket ownership if behavior/lifecycle wording changes.
- `taskplane-tasks/CONTEXT.md` — record migration result.

**Check If Affected:**
- `docs/task-schedule-mvp.md` — update if smoke/log paths change.

## Completion Criteria

- [ ] All steps complete
- [ ] All tests passing with evidence recorded in STATUS.md
- [ ] Protocol frame ordering preserved or explicitly covered by regression tests
- [ ] Documentation updated
- [ ] Exactly one final TP commit exists

## Git Commit Convention

Commits happen at **step boundaries** (not after every checkbox). The final integrated history must squash this task into exactly one TP commit.

Recommended final commit subject:

`TP-037: Migrate LogIngest ROUTER to EventLoop`

## Do NOT

- Expand scope into unrelated feature work; log follow-ups in `taskplane-tasks/CONTEXT.md`
- Claim exactly-once logging delivery
- Change ZMQ multipart frame ordering without explicit regression coverage
- Couple worker logging backpressure to task/status backend traffic
- Commit a final history with more than one commit for this TP

---

## Amendments (Added During Execution)

<!-- Workers add amendments here if issues discovered during execution. -->
