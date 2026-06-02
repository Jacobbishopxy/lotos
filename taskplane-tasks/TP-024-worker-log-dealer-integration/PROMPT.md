# Task: TP-024 - Worker DEALER Log Transport Integration

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Switches the worker logging transport and broker runtime wiring across worker/broker/demo paths. It affects multiple services but follows the protocol established by prior TPs.
**Score:** 5/8 — Blast radius: 2, Pattern novelty: 2, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-024-worker-log-dealer-integration/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Move workers from best-effort PUB logging to the reliable LogBatch DEALER channel. Add worker-side bounded buffering, batch send/retry, ACK handling, and dropped-log accounting while preserving task execution behavior and exposing log health through worker status or the log stats endpoint.

## Dependencies

- **Task:** TP-023 (must complete before this dependent logging redesign stage)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `AGENTS.md` — repository rules, especially Cabal verification and 1 TP = 1 commit expectations
- `docs/logging-redesign.md` — logging migration design, once created by TP-021
- `docs/lb_sys.drawio` — current architecture diagram
- `lotos/src/Lotos/Zmq/Adt.hs` — protocol frame contracts
- `lotos/src/Lotos/Zmq/Config.hs` — broker/worker config records
- `lotos/src/Lotos/Zmq/LBS/InfoStorage.hs` — current logging coupling to replace
- `lotos/src/Lotos/Zmq/LBW.hs` — current worker logging send path

## Environment

- **Workspace:** lotos core library, TaskSchedule demo, and docs as scoped below
- **Services required:** None for implementation; smoke scripts for final verification where listed

## File Scope

- `lotos/src/Lotos/Zmq/LBW.hs`
- `lotos/src/Lotos/Zmq/LBS.hs`
- `lotos/src/Lotos/Zmq/LBS/InfoStorage.hs`
- `lotos/src/Lotos/Zmq/LBS/LogIngest.hs`
- `lotos/src/Lotos/Zmq/Config.hs`
- `lotos/src/Lotos/Zmq/Adt.hs`
- `applications/TaskSchedule/src/Worker.hs`
- `applications/TaskSchedule/app/TaskScheduleWorker.hs`
- `applications/TaskSchedule/app/TaskScheduleServer.hs`
- `applications/TaskSchedule/config/*`
- `lotos/test/*`
- `applications/TaskSchedule/test/*`
- `docs/logging-redesign.md`
- `taskplane-tasks/TP-024-worker-log-dealer-integration/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Plan worker-side reliability semantics


- [ ] Plan-review checkpoint — define worker queue limits, batch flush triggers, retry/ACK timeout behavior, and drop priority.

- [ ] Define how dropped-log counts and sequence gaps surface to operators.

- [ ] Ensure task execution cannot deadlock indefinitely on log transport failure.

### Step 2: Implement worker transport switch


- [ ] Replace PUB send path with DEALER LogBatch sender and ACK reader, preferably on a separate logging socket/channel from task backend traffic.

- [ ] Preserve task stdout/stderr/final-result logging semantics as LogEvent streams/levels.

- [ ] Update broker startup/config to run LogIngest with the new logging address and keep or remove old SUB path according to compatibility needs.

- [ ] Add tests for ACK/retry/drop behavior using bounded fakes where ZMQ integration would be slow.

### Step 3: Testing & Verification


- [ ] Code review checkpoint — review runtime failure modes and config compatibility.

- [ ] Run targeted worker/log transport tests.

- [ ] Run `cabal build all --enable-tests` and terminating regression suites touched by the transport change.

### Step 4: Documentation & Delivery


- [ ] Update docs/config examples with the new reliable log transport.

- [ ] Update CONTEXT to mark PUB/SUB logging replacement status.

## Documentation Requirements

**Must Update:**
- `docs/logging-redesign.md — implementation details and runtime caveats`
- `taskplane-tasks/CONTEXT.md — status`

**Check If Affected:**
- `README.md`
- `docs/task-schedule-mvp.md`
- `docs/build-your-own-scheduler.md`

## Completion Criteria

- [ ] The TP's scoped logging redesign deliverable is complete
- [ ] Existing behavior outside this TP's stage is preserved or intentionally documented
- [ ] Targeted tests/build/smoke listed above pass
- [ ] Documentation and CONTEXT are updated
- [ ] Final history contains exactly one commit for this TP, with Lore trailers

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-024` and Lore trailers.

## Do NOT

- Add third-party dependencies unless explicitly justified and accepted by existing project rules
- Break ZMQ multipart frame ordering for existing messages
- Claim exactly-once log delivery; target at-least-once with idempotent ingestion unless the design explicitly changes
- Leave unbounded log memory growth
- Hide dropped logs or sequence gaps
- Mix changes from a later dependent TP into this TP

---

## Amendments (Added During Execution)
