# Task: TP-048 - Golden protocol frame fixtures

**Created:** 2026-06-04
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** This adds regression fixtures around the ZMQ wire ABI and old-frame compatibility. It touches protocol tests and documentation but should not change runtime behavior except to expose test helpers if needed.
**Score:** 4/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 2

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-048-golden-protocol-frame-fixtures/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Back TP-046's protocol compatibility policy with golden frame fixture tests for the most important ZMQ multipart payloads. The tests should make positional frame ordering, append-only old-frame fallbacks, and task-ID invariants hard to break accidentally.

## Dependencies

- **Task:** TP-047 (smoke hardening complete)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `lotos/src/Lotos/Zmq/Adt.hs` — protocol types and ToZmq/FromZmq instances
- `lotos/test/ZmqWorkerFrames.hs` — existing frame regression tests
- `lotos/test/ZmqClientAckFrames.hs` — client ACK frame tests
- `lotos/test/ZmqLogProtocolConfig.hs` — logging compatibility tests
- `docs/book/lotos/src/protocol-compatibility.md` — compatibility policy

## Environment

- **Workspace:** `lotos/` package and TaskSchedule tests
- **Services required:** None

## File Scope

- `lotos/test/*`
- `lotos/lotos.cabal`
- `applications/TaskSchedule/test/Scheduler.hs`
- `applications/TaskSchedule/TaskSchedule.cabal`
- `docs/book/lotos/src/protocol-compatibility.md`
- `docs/book/lotos/src/zmq-protocol.md`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied

### Step 1: Design golden fixture shape

- [ ] Inventory existing frame tests and identify missing golden coverage for task requests, client ACKs, worker state, worker task status, worker reports, and log batches/ACKs
- [ ] Choose in-code fixture constants or checked-in fixture data; prefer simple Haskell constants unless external files materially improve clarity
- [ ] Ensure tests assert exact frame counts/order and legacy fallback decoding where policy permits
- [ ] Run targeted existing frame tests before edits: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames`

**Artifacts:**
- `lotos/test/*` (modified/new)

### Step 2: Add golden protocol tests

- [ ] Add exact round-trip/golden tests for core request/status/ACK payloads
- [ ] Add explicit old-frame fallback fixture for append-only worker-state capacity evolution
- [ ] Add negative tests for malformed or wrong-order frames where existing patterns support it
- [ ] Register any new test suite in `lotos/lotos.cabal` only if extending existing suites is not clean
- [ ] Run targeted tests: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames lotos:test:test-zmq-log-protocol-config`

**Artifacts:**
- `lotos/test/*` (modified/new)
- `lotos/lotos.cabal` (modified if needed)

### Step 3: Align docs with fixture coverage

- [ ] Update compatibility docs to point future protocol changes at the golden tests
- [ ] Update ZMQ protocol docs if fixture work clarifies payload shapes
- [ ] Log any unsupported compatibility gap in `taskplane-tasks/CONTEXT.md`

**Artifacts:**
- `docs/book/lotos/src/protocol-compatibility.md` (modified)
- `docs/book/lotos/src/zmq-protocol.md` (modified if needed)

### Step 4: Testing & Verification

- [ ] Run FULL build gate: `cabal build all --enable-tests`
- [ ] Run targeted protocol tests: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames lotos:test:test-zmq-log-protocol-config`
- [ ] Run docs gate: `make book-build`
- [ ] Fix all failures

### Step 5: Documentation & Delivery

- [ ] "Must Update" docs modified
- [ ] "Check If Affected" docs reviewed
- [ ] Discoveries logged in STATUS.md and context if future work remains

## Documentation Requirements

**Must Update:**
- `docs/book/lotos/src/protocol-compatibility.md` — document golden fixture coverage and change requirements

**Check If Affected:**
- `docs/book/lotos/src/zmq-protocol.md` — update exact payload examples if tests clarify them
- `taskplane-tasks/CONTEXT.md` — log discoveries or future gaps

## Completion Criteria

- [ ] Golden frame tests protect exact ordering for core protocol payloads
- [ ] Legacy append-only fallback is covered by fixtures
- [ ] Targeted protocol tests, full build, and docs build pass

## Git Commit Convention

Commits happen at **step boundaries** and MUST include `TP-048`.

## Do NOT

- Change ZMQ multipart frame ordering
- Remove old-frame decode compatibility without a versioned migration
- Add dependencies
- Skip exact frame-order assertions

---

## Amendments (Added During Execution)
