# Task: TP-004 - Align TaskSchedule Runtime Config

**Created:** 2026-05-31
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Aligns server, worker, and client runtime wiring. It spans multiple entry points but should remain reversible because it uses existing config types.
**Score:** 4/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-004-align-runtime-config/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Make the TaskSchedule runtime consistently configurable and correct the hardcoded address mismatch between server, worker, and client. The outcome should let a user run server, worker, and client with documented defaults or explicit JSON config files.

## Dependencies

- **Task:** TP-002 (runtime contract must be complete)
- **Task:** TP-003 (client behavior should be known before final config examples)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `docs/task-schedule-mvp.md` — canonical runtime contract
- `applications/TaskSchedule/app/TaskScheduleServer.hs` — server defaults/config loading
- `applications/TaskSchedule/app/TaskScheduleWorker.hs` — worker defaults/config loading
- `applications/TaskSchedule/app/TaskScheduleClient.hs` — client defaults/config loading
- `lotos/src/Lotos/Zmq/Config.hs` — existing config types/readers
- `README.md` — current documented caveat about address mismatch

## Environment

- **Workspace:** `applications/TaskSchedule`
- **Services required:** None for build checks

## File Scope

- `applications/TaskSchedule/app/TaskScheduleServer.hs`
- `applications/TaskSchedule/app/TaskScheduleWorker.hs`
- `applications/TaskSchedule/app/TaskScheduleClient.hs`
- `applications/TaskSchedule/config/*` (new sample configs if chosen by contract)
- `applications/TaskSchedule/TaskSchedule.cabal` (only if needed)
- `docs/task-schedule-mvp.md`
- `README.md`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] TP-002 and TP-003 completion criteria are satisfied

### Step 1: Plan runtime wiring

**Plan-review checkpoint** — review address/config decisions before touching all entry points.

- [ ] Confirm frontend/backend/logging addresses from the runtime contract
- [ ] Decide default config behavior vs explicit config file loading
- [ ] Identify minimal edits needed across server, worker, and client

### Step 2: Implement aligned config/defaults

- [ ] Server defaults/config loading match contract
- [ ] Worker defaults/config loading connect to the server backend/logging addresses correctly
- [ ] Client defaults/config loading connect to the server frontend correctly
- [ ] Sample configs added if the contract calls for them

### Step 3: Testing & Verification

**Code review checkpoint** — review final wiring changes before completion.

- [ ] Build passes: `cabal build TaskSchedule:exe:ts-server TaskSchedule:exe:ts-worker TaskSchedule:exe:ts-client`
- [ ] Build all passes: `cabal build all`
- [ ] Static inspection confirms server/worker/client addresses are consistent

### Step 4: Documentation & Delivery

- [ ] README no longer claims the address wiring is likely inverted if fixed
- [ ] `docs/task-schedule-mvp.md` reflects final config/default behavior
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `docs/task-schedule-mvp.md` — final defaults/config details
- `README.md` — remove stale caveat and update run commands if relevant

**Check If Affected:**
- `taskplane-tasks/CONTEXT.md` — append any follow-up debt discovered

## Completion Criteria

- [ ] Server, worker, and client use consistent addresses/config
- [ ] The hardcoded mismatch is resolved or explicitly configured
- [ ] Builds pass
- [ ] Docs reflect current behavior

## Git Commit Convention

Commits happen at step boundaries. All commits for this task MUST include the task ID for traceability.

## Do NOT

- Change core ZMQ protocol frame ordering
- Add a new config library; use existing Aeson/YAML utilities and config types
- Implement smoke automation beyond what is needed to verify wiring

---

## Amendments (Added During Execution)
