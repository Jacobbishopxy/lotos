# Task: TP-045 - Deprecate legacy logging names with compatibility path

**Created:** 2026-06-04
**Size:** L

## Review Level: 3 (Full)

**Assessment:** Touches public config/API names and compatibility behavior. Requires careful migration docs and tests to avoid breaking existing JSON/configs unexpectedly.
**Score:** 6/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 3

## Canonical Task Folder

```
/home/xiey/Code/lotos/taskplane-tasks/TP-045-legacy-logging-api-compatibility-cleanup/
├── PROMPT.md   ← This file (immutable above --- divider)
├── STATUS.md   ← Execution state (worker updates this)
├── .reviews/   ← Reviewer output (created by the orchestrator runtime)
└── .DONE       ← Created when complete
```

## Mission

Clean up legacy logging names left over from the PUB/SUB era by introducing clearer LogIngest-oriented names while keeping old JSON/API compatibility where appropriate.

## Dependencies

- **Task:** TP-044 (scheduler/capacity runtime follow-up complete; docs book available for migration guidance)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `/home/xiey/Code/arcadia-lob/Makefile.toml` — reference style for mdBook build/serve/help command design.
- `Makefile` — existing project command surface.
- `docs/logging-redesign.md` — logging architecture and compatibility context.
- `docs/task-schedule-mvp.md` — TaskSchedule runtime/smoke context.
- `docs/build-your-own-scheduler.md` — scheduler API/adopter context.

## Environment

- **Workspace:** `/home/xiey/Code/lotos`
- **Services required:** None unless smoke verification steps explicitly start TaskSchedule services.

## File Scope

- `lotos/src/Lotos/Zmq/Config.hs`
- `lotos/src/Lotos/Zmq/LBW.hs`
- `lotos/src/Lotos/Zmq.hs`
- `applications/TaskSchedule/config/*.json`
- `docs/logging-redesign.md`
- `docs/book/lotos/src/*`
- `README.md`
- `taskplane-tasks/CONTEXT.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied
- [ ] Current git/task status reviewed so this TP finishes as exactly one final commit

### Step 1: Plan compatibility surface

- [ ] Plan-review checkpoint — inventory legacy names: `infoStorage.loggingAddr`, `infoStorage.loggingsBufferSize`, `loadBalancerLoggingAddr`, `taPubTaskLogging`, and related docs/config defaults.
- [ ] Decide new names and whether old record fields remain, get deprecated comments, or move to compatibility-only JSON parsing.
- [ ] Define migration examples for old and new broker/worker JSON.

### Step 2: Implement compatibility cleanup

- [ ] Add new clearer names/default derivation where feasible without breaking existing configs.
- [ ] Keep old JSON keys accepted and tested; emit docs/comments explaining compatibility behavior.
- [ ] Rename internal comments/usages that no longer reflect runtime LogIngest behavior.

### Step 3: Add tests

- [ ] Add config parse tests for old and new logging keys.
- [ ] Verify TaskSchedule checked-in configs still parse.
- [ ] Verify reliable logging smoke paths remain unchanged.

### Step 4: Testing & Verification

- [ ] Code review checkpoint — review public API compatibility and docs.
- [ ] Run log protocol/config tests, LogIngest tests, worker log transport tests.
- [ ] Run `cabal build all --enable-tests`.
- [ ] Run single-worker smoke.

### Step 5: Documentation & Delivery

- [ ] Update `docs/logging-redesign.md` and mdBook API/operations pages with the migration path.
- [ ] Mark legacy logging-name debt resolved in `taskplane-tasks/CONTEXT.md`.
- [ ] Ensure exactly one final TP commit exists.

## Documentation Requirements

**Must Update:**
- `docs/logging-redesign.md` — document new/legacy logging names.
- `docs/book/lotos/src/api.md` — document compatibility path.
- `taskplane-tasks/CONTEXT.md` — mark debt resolved if complete.

**Check If Affected:**
- `README.md` — update public config examples if names change.

## Completion Criteria

- [ ] All steps complete
- [ ] Tests/build/smoke evidence recorded in STATUS.md
- [ ] Documentation updated
- [ ] Exactly one final TP commit exists

## Git Commit Convention

Final integrated history must squash this task into exactly one TP commit.

Recommended final commit subject:

`TP-045: Deprecate legacy logging names with compatibility path`

## Do NOT

- Change ZMQ multipart frame ordering without explicit tests and documented compatibility reasoning
- Convert no-drop task/status queues into dropping queues unless the prompt explicitly allows it
- Claim exactly-once logging delivery
- Add non-Cabal build dependencies unless the task explicitly scopes them as optional docs tooling
- Leave final history with more than one commit for this TP

---

## Amendments (Added During Execution)

<!-- Workers add amendments here if issues discovered during execution. -->
