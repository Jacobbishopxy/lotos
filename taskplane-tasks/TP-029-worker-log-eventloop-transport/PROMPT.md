# Task: TP-029 - Move Worker Log Transport to Zmqx EventLoop

**Created:** 2026-06-03
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Migrates the reliable worker log DEALER to zmqx EventLoop transceiver ownership. It changes concurrency/ACK handling in the logging transport but should preserve the existing LogBatch/LogAck protocol.
**Score:** 5/8 — Blast radius: 2, Pattern novelty: 2, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-029-worker-log-eventloop-transport/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Use `Zmqx.EventLoop` where it fits best: the worker logging DEALER. The log socket should be owned by an EventLoop transceiver so ACK reception is continuously active and send/receive ownership is centralized, while preserving at-least-once retry/drop semantics and existing `/logs/*` smoke evidence.

## Dependencies

- **Task:** TP-028 (worker responsiveness cleanup complete)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `AGENTS.md` — project rules, Cabal verification, and 1 TP = 1 commit expectation
- `cabal.project` — current `zmqx` source-repository pin
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/README.md` — zmqx v0.1.1.x API guidance after dependency materialization
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/EventLoop.hs` — EventLoop API details if migrating socket ownership
- `dist-newstyle/src/zmqx-c57178d77b1b9236a637c009fb09031ef5c750bb8464a12ea6ccb47f347f3aec/lib/Zmqx/Monad.hs` — monad-style context API details if relevant
- `lotos/src/Lotos/Zmq/LBW.hs` — worker backend/task execution loop
- `lotos/src/Lotos/Zmq/LBW/LogTransport.hs` — reliable worker log transport
- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs` — broker socket loop
- `lotos/src/Lotos/Zmq/LBS/LogIngest.hs` — broker reliable log ingestion

## Environment

- **Workspace:** lotos core library, TaskSchedule demo, and docs as scoped below
- **Services required:** None for unit tests; smoke scripts for final verification where listed

## File Scope

- `lotos/src/Lotos/Zmq/LBW/LogTransport.hs`
- `lotos/src/Lotos/Zmq/LBW.hs`
- `lotos/test/ZmqWorkerLogTransport.hs`
- `lotos/test/ZmqLogIngest.hs`
- `lotos/lotos.cabal (only if adding tests)`
- `docs/logging-redesign.md`
- `scripts/task-schedule-smoke.sh`
- `scripts/task-schedule-multi-worker-smoke.sh`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-029-worker-log-eventloop-transport/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Design EventLoop transport boundary

- [ ] Plan-review checkpoint — map current worker log send/ACK/retry state machine to `Zmqx.addTransceiver` and mailbox/callback semantics.
- [ ] Decide whether ACK handling uses EventLoop mailbox polling or callback delivery, and define shutdown behavior.
- [ ] Define tests that prove ACKs can arrive independently of send retries and that socket ownership is not violated.

### Step 2: Implement EventLoop-backed log transport

- [ ] Open the worker log DEALER and register it as an EventLoop transceiver under a stable endpoint name.
- [ ] Route LogBatch sends through `Zmqx.EventLoop.sends` and ACK receives through EventLoop `recv` or callback handling.
- [ ] Preserve queue HWM, retry backoff, rejected-batch gap markers, and drop accounting.
- [ ] Keep LogIngest server API/protocol unchanged.

### Step 3: Testing & Verification

- [ ] Code review checkpoint — review socket ownership and concurrency lifecycle.
- [ ] Run `cabal test lotos:test:test-zmq-worker-log-transport lotos:test:test-zmq-log-ingest lotos:test:test-zmq-log-protocol-config`.
- [ ] Run `cabal build all --enable-tests`.
- [ ] Run TaskSchedule smoke scripts if worker logging runtime changed end-to-end.

### Step 4: Documentation & Delivery

- [ ] Update `docs/logging-redesign.md` with EventLoop ownership details and caveats.
- [ ] Update `taskplane-tasks/CONTEXT.md` with remaining EventLoop migration status.

## Documentation Requirements

**Must Update:**
- `docs/logging-redesign.md — worker log EventLoop ownership`
- `taskplane-tasks/CONTEXT.md — status`

**Check If Affected:**
- `docs/task-schedule-mvp.md`
- `README.md`

## Completion Criteria

- [ ] This TP's scoped zmqx/EventLoop/performance deliverable is complete
- [ ] Existing ZMQ multipart frame ordering is preserved
- [ ] Targeted tests/build/smoke listed above pass or gaps are documented honestly
- [ ] Documentation and CONTEXT are updated
- [ ] Final history contains exactly one commit for TP-029, with Lore trailers

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-029` and Lore trailers.

## Do NOT

- Add third-party dependencies unless explicitly justified and accepted by existing project rules
- Change existing task/status/log frame ordering
- Claim performance wins without a test, smoke result, benchmark, or clearly bounded rationale
- Mix changes from later dependent TPs into this TP
- Leave runtime hot loops with unconditional stdout logging

---

## Amendments (Added During Execution)
