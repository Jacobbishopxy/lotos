# Task: TP-022 - Reliable Log Protocol and Config

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Introduces new protocol/config surface in the core library while preserving existing runtime behavior. The change touches public/internal ZMQ types and tests but should remain backward-compatible until later TPs switch transports.
**Score:** 5/8 — Blast radius: 2, Pattern novelty: 2, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-022-log-protocol-config/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Introduce structured log event, batch, ACK, and logging configuration types that can support reliable worker log ingestion. Keep the current PUB/SUB runtime path working while adding bounded tests for serialization, sequence metadata, and configuration defaults.

## Dependencies

- **Task:** TP-021 (must complete before this dependent logging redesign stage)

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

- `lotos/src/Lotos/Zmq/Adt.hs`
- `lotos/src/Lotos/Zmq/Config.hs`
- `lotos/src/Lotos/Zmq.hs`
- `lotos/test/*`
- `lotos/lotos.cabal`
- `docs/logging-redesign.md`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-022-log-protocol-config/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Design protocol compatibility boundary


- [ ] Plan-review checkpoint — decide names/exports for `LogEvent`, `LogBatch`, `LogAck`, stream/level/drop-policy types, and whether they are public via `Lotos.Zmq`.

- [ ] Preserve existing `WorkerLogging` frame ordering and compatibility until the transport switch TP removes or adapts it.

- [ ] Define config defaults and backward-compatible JSON parsing for existing broker/worker configs.

### Step 2: Implement protocol/config and tests


- [ ] Add structured log protocol types and ToZmq/FromZmq/Aeson coverage.

- [ ] Add logging config knobs for ROUTER/DEALER address, HWM, batch size, line size, cache limits, persistence path, retention, and drop policy.

- [ ] Update exports/documentation comments without adding dependencies.

### Step 3: Testing & Verification


- [ ] Code review checkpoint — review protocol frame ordering and config compatibility.

- [ ] Run targeted protocol/config tests.

- [ ] Run `cabal build all --enable-tests` and a targeted terminating test suite relevant to changed code.

### Step 4: Documentation & Delivery


- [ ] Update `docs/logging-redesign.md` with exact type/config names if they differ from the initial design.

- [ ] Update CONTEXT with remaining logging transport work.

## Documentation Requirements

**Must Update:**
- `docs/logging-redesign.md — keep type/config plan accurate`
- `taskplane-tasks/CONTEXT.md — update logging roadmap status`

**Check If Affected:**
- `README.md`
- `docs/build-your-own-scheduler.md`

## Completion Criteria

- [ ] The TP's scoped logging redesign deliverable is complete
- [ ] Existing behavior outside this TP's stage is preserved or intentionally documented
- [ ] Targeted tests/build/smoke listed above pass
- [ ] Documentation and CONTEXT are updated
- [ ] Final history contains exactly one commit for this TP, with Lore trailers

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-022` and Lore trailers.

## Do NOT

- Add third-party dependencies unless explicitly justified and accepted by existing project rules
- Break ZMQ multipart frame ordering for existing messages
- Claim exactly-once log delivery; target at-least-once with idempotent ingestion unless the design explicitly changes
- Leave unbounded log memory growth
- Hide dropped logs or sequence gaps
- Mix changes from a later dependent TP into this TP

---

## Amendments (Added During Execution)
