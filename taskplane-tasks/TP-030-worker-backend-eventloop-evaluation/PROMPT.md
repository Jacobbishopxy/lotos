# Task: TP-030 - Evaluate Worker Backend EventLoop Migration

**Created:** 2026-06-03
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Potentially migrates the worker backend DEALER/internal PAIR loop to EventLoop or documents why direct polling remains better. It touches task/status runtime traffic and must be conservative.
**Score:** 5/8 — Blast radius: 2, Pattern novelty: 2, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-030-worker-backend-eventloop-evaluation/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Evaluate and, if beneficial, migrate the worker backend socket loop to `Zmqx.EventLoop` ownership. This loop currently polls the backend DEALER plus an internal PAIR for task status forwarding; the TP should either land a safe EventLoop transceiver/receiver design or leave direct polling in place with documented reasons and tests.

## Dependencies

- **Task:** TP-029 (worker log EventLoop transport complete)

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

- `lotos/src/Lotos/Zmq/LBW.hs`
- `lotos/src/Lotos/Zmq/LBW/LogTransport.hs (only for coordination)`
- `lotos/test/ZmqWorkerFrames.hs`
- `lotos/test/ZmqWorkerLogTransport.hs`
- `applications/TaskSchedule/test/*`
- `scripts/task-schedule-smoke.sh`
- `scripts/task-schedule-multi-worker-smoke.sh`
- `docs/logging-redesign.md`
- `docs/task-schedule-mvp.md`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-030-worker-backend-eventloop-evaluation/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Evaluate fit and choose path

- [ ] Plan-review checkpoint — compare direct poll loop vs EventLoop for worker backend DEALER + internal PAIR.
- [ ] Identify hazards: callbacks blocking worker status, preserving task enqueue order, status forwarding latency, and shutdown behavior.
- [ ] Decide whether to implement migration or explicitly keep direct polling.

### Step 2: Implement or document outcome

- [ ] If migrating: register backend DEALER as transceiver and internal PAIR as receiver/sender as appropriate, with bounded mailbox/callback behavior.
- [ ] If not migrating: remove any remaining easy inefficiencies in the direct loop and document why EventLoop is not a net improvement yet.
- [ ] Preserve worker task receive/status report frame ordering and liveness semantics.

### Step 3: Testing & Verification

- [ ] Code review checkpoint — review task/status traffic correctness.
- [ ] Run worker frame tests, worker lifecycle tests, and reliable log tests.
- [ ] Run `cabal build all --enable-tests`.
- [ ] Run single-worker smoke; run multi-worker smoke if status/scheduling behavior changed.

### Step 4: Documentation & Delivery

- [ ] Update docs/CONTEXT with the worker backend EventLoop decision and remaining risks.

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md — EventLoop decision/status`

**Check If Affected:**
- `docs/logging-redesign.md`
- `docs/task-schedule-mvp.md`
- `README.md`

## Completion Criteria

- [ ] This TP's scoped zmqx/EventLoop/performance deliverable is complete
- [ ] Existing ZMQ multipart frame ordering is preserved
- [ ] Targeted tests/build/smoke listed above pass or gaps are documented honestly
- [ ] Documentation and CONTEXT are updated
- [ ] Final history contains exactly one commit for TP-030, with Lore trailers

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-030` and Lore trailers.

## Do NOT

- Add third-party dependencies unless explicitly justified and accepted by existing project rules
- Change existing task/status/log frame ordering
- Claim performance wins without a test, smoke result, benchmark, or clearly bounded rationale
- Mix changes from later dependent TPs into this TP
- Leave runtime hot loops with unconditional stdout logging

---

## Amendments (Added During Execution)
