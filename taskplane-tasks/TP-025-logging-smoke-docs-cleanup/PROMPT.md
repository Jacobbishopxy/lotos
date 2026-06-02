# Task: TP-025 - Logging Smoke, Docs, and Compatibility Cleanup

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Finishes the migration by updating smoke scripts, docs, and compatibility cleanup across demo and library surfaces. It validates end-to-end behavior but should avoid introducing new architecture.
**Score:** 4/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-025-logging-smoke-docs-cleanup/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Complete the reliable logging migration by proving task logs through the new `/logs` API in smoke tests, removing obsolete InfoStorage full-log assumptions, updating documentation/examples, and normalizing the final architecture diagram.

## Dependencies

- **Task:** TP-024 (must complete before this dependent logging redesign stage)

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

- `scripts/task-schedule-smoke.sh`
- `scripts/task-schedule-multi-worker-smoke.sh`
- `README.md`
- `docs/task-schedule-mvp.md`
- `docs/build-your-own-scheduler.md`
- `docs/logging-redesign.md`
- `docs/lb_sys.drawio`
- `lotos/src/Lotos/Zmq/LBS/InfoStorage.hs`
- `lotos/src/Lotos/Zmq/LBS/LogIngest.hs`
- `applications/TaskSchedule/app/*`
- `applications/TaskSchedule/config/*`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-025-logging-smoke-docs-cleanup/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Update end-to-end smoke expectations


- [ ] Plan-review checkpoint — identify deterministic `/logs` assertions for single-worker and multi-worker smokes.

- [ ] Update smoke scripts to verify current-run stdout/final-result logs through `/logs` endpoints instead of `/info.workerLoggingsMap`.

- [ ] Add stats/dropped-log assertions where deterministic.

### Step 2: Cleanup obsolete logging coupling


- [ ] Remove or deprecate InfoStorage full-log fields/API once smoke and docs use LogIngest.

- [ ] Ensure `/info` remains lightweight and still exposes scheduler state.

- [ ] Refresh `docs/lb_sys.drawio` to show the final LogIngest architecture with no overlapping labels.

### Step 3: Testing & Verification


- [ ] Code review checkpoint — review final API/docs/smoke consistency.

- [ ] Run `cabal build all --enable-tests`.

- [ ] Run `cabal test all` if it remains bounded/safe.

- [ ] Run `scripts/task-schedule-smoke.sh` and `scripts/task-schedule-multi-worker-smoke.sh`.

### Step 4: Documentation & Delivery


- [ ] Update README and docs with new logging behavior, endpoints, limits, and reliability caveats.

- [ ] Update CONTEXT to close or refine logging redesign debt.

## Documentation Requirements

**Must Update:**
- `README.md — user-facing logging behavior if changed`
- `docs/task-schedule-mvp.md — smoke/log evidence path`
- `docs/logging-redesign.md — final status`
- `docs/lb_sys.drawio — final architecture`

**Check If Affected:**
- `docs/build-your-own-scheduler.md`

## Completion Criteria

- [ ] The TP's scoped logging redesign deliverable is complete
- [ ] Existing behavior outside this TP's stage is preserved or intentionally documented
- [ ] Targeted tests/build/smoke listed above pass
- [ ] Documentation and CONTEXT are updated
- [ ] Final history contains exactly one commit for this TP, with Lore trailers

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-025` and Lore trailers.

## Do NOT

- Add third-party dependencies unless explicitly justified and accepted by existing project rules
- Break ZMQ multipart frame ordering for existing messages
- Claim exactly-once log delivery; target at-least-once with idempotent ingestion unless the design explicitly changes
- Leave unbounded log memory growth
- Hide dropped logs or sequence gaps
- Mix changes from a later dependent TP into this TP

---

## Amendments (Added During Execution)
