# Task: TP-031 - Evaluate Broker SocketLayer EventLoop Migration

**Created:** 2026-06-03
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Assesses the broker socket layer after worker-side wins are complete. It may migrate frontend/backend/internal polling to EventLoop or keep direct polling with cleanup; this touches core task routing.
**Score:** 5/8 — Blast radius: 2, Pattern novelty: 2, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-031-broker-socketlayer-eventloop-evaluation/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Evaluate whether the broker `SocketLayer` should use `Zmqx.EventLoop` for frontend ROUTER, backend ROUTER, and TaskProcessor PAIR traffic. The goal is socket-ownership safety and potential polling/send fairness, not broad protocol redesign.

## Dependencies

- **Task:** TP-030 (worker backend EventLoop decision complete)

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

- `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs`
- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs (only if internal PAIR contracts change)`
- `lotos/test/ZmqClientAckFrames.hs`
- `lotos/test/ZmqWorkerFrames.hs`
- `lotos/test/ZmqLogIngest.hs`
- `scripts/task-schedule-smoke.sh`
- `scripts/task-schedule-multi-worker-smoke.sh`
- `docs/lb_sys.drawio (only if architecture changes materially)`
- `docs/task-schedule-mvp.md`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-031-broker-socketlayer-eventloop-evaluation/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Evaluate broker EventLoop fit

- [ ] Plan-review checkpoint — map frontend ROUTER, backend ROUTER, and internal PAIR roles to EventLoop sender/receiver/transceiver modes.
- [ ] Identify whether callbacks would be too heavy for queue/map mutation and whether mailbox-based dispatch is safer.
- [ ] Decide implement vs defer based on concrete benefit and risk.

### Step 2: Implement selected broker path

- [ ] If migrating: centralize socket ownership in EventLoop while preserving ClientAck, WorkerTask, WorkerStatus, WorkerTaskStatus, retry, garbage, and notify frame ordering.
- [ ] If deferring: keep direct poll but remove remaining inefficiencies and document the rationale.
- [ ] Do not change public ZMQ multipart shapes.

### Step 3: Testing & Verification

- [ ] Code review checkpoint — review protocol/frame and scheduler interaction correctness.
- [ ] Run protocol frame tests, worker frame tests, client ACK tests, scheduler/worker lifecycle tests.
- [ ] Run `cabal build all --enable-tests`.
- [ ] Run single-worker and multi-worker smoke scripts.

### Step 4: Documentation & Delivery

- [ ] Update docs/CONTEXT with the broker EventLoop decision and any remaining performance debt.
- [ ] Update `docs/lb_sys.drawio` only if the architecture changes visibly.

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md — broker EventLoop decision/status`

**Check If Affected:**
- `docs/lb_sys.drawio`
- `docs/task-schedule-mvp.md`
- `README.md`

## Completion Criteria

- [ ] This TP's scoped zmqx/EventLoop/performance deliverable is complete
- [ ] Existing ZMQ multipart frame ordering is preserved
- [ ] Targeted tests/build/smoke listed above pass or gaps are documented honestly
- [ ] Documentation and CONTEXT are updated
- [ ] Final history contains exactly one commit for TP-031, with Lore trailers

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-031` and Lore trailers.

## Do NOT

- Add third-party dependencies unless explicitly justified and accepted by existing project rules
- Change existing task/status/log frame ordering
- Claim performance wins without a test, smoke result, benchmark, or clearly bounded rationale
- Mix changes from later dependent TPs into this TP
- Leave runtime hot loops with unconditional stdout logging

---

## Amendments (Added During Execution)
