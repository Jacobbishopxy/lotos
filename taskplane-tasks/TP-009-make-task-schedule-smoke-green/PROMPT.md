# Task: TP-009 - Make TaskSchedule Smoke Green

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Validates and tightens the final product smoke path across server, worker, client, and docs. It should mostly adjust smoke tooling/docs after TP-007 and TP-008 unblock runtime behavior.
**Score:** 4/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 2

## Canonical Task Folder

```
taskplane-tasks/TP-009-make-task-schedule-smoke-green/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Make `scripts/task-schedule-smoke.sh` exit `0` for the TaskSchedule MVP path, or document a single exact remaining product blocker if a fully green run is still impossible. This task should consume the runtime fixes from TP-007 and TP-008 and produce final smoke evidence.

## Dependencies

- **Task:** TP-007 (worker stats visible)
- **Task:** TP-008 (client ACK works)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `docs/task-schedule-mvp.md` — smoke contract and current evidence notes
- `scripts/task-schedule-smoke.sh` — smoke helper
- `README.md` — run/test guidance
- `applications/TaskSchedule/config/*.json` — sample runtime configs
- `applications/TaskSchedule/app/TaskScheduleServer.hs`
- `applications/TaskSchedule/app/TaskScheduleWorker.hs`
- `applications/TaskSchedule/app/TaskScheduleClient.hs`

## Environment

- **Workspace:** TaskSchedule smoke tooling/docs
- **Services required:** Local server/worker/client started by smoke script

## File Scope

- `scripts/task-schedule-smoke.sh`
- `docs/task-schedule-mvp.md`
- `README.md`
- `applications/TaskSchedule/config/*` (only if sample config adjustments are required)
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-009-make-task-schedule-smoke-green/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] TP-007 and TP-008 completion criteria are satisfied or exact residual blockers are known

### Step 1: Re-run and inspect smoke evidence

**Plan-review checkpoint** — review any proposed smoke script changes before editing.

- [ ] Run `cabal build all --enable-tests`
- [ ] Run `scripts/task-schedule-smoke.sh` with timeout-safe cleanup
- [ ] Inspect evidence directory, logs, info snapshots, and marker output

### Step 2: Tighten smoke script/docs if needed

- [ ] Patch smoke script only for stale assumptions, readiness timing, cleanup, or evidence clarity
- [ ] Do not paper over product failures; fix upstream code only if clearly in scope and small
- [ ] Keep run evidence paths and exit codes documented

### Step 3: Testing & Verification

**Code review checkpoint** — review final smoke evidence before completion.

- [ ] `cabal build all --enable-tests` passes
- [ ] `scripts/task-schedule-smoke.sh` exits `0`, or exact blocker is captured with logs
- [ ] Worker stats, client ACK, and marker file proof are verified for a green run

### Step 4: Documentation & Delivery

- [ ] README smoke instructions reflect final behavior
- [ ] MVP doc current-status section is accurate
- [ ] Context debt list updated to remove resolved blockers or add exact follow-up

## Documentation Requirements

**Must Update:**
- `docs/task-schedule-mvp.md` — final smoke evidence/status
- `README.md` — smoke instructions if changed
- `taskplane-tasks/CONTEXT.md` — resolve/refine runtime debt

**Check If Affected:**
- `applications/TaskSchedule/config/*` — ensure docs match samples

## Completion Criteria

- [ ] Smoke script exits `0` and proves client → broker → worker → marker/status path, or one exact remaining blocker is documented
- [ ] Build/test gate passes
- [ ] Docs match reality

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-009` and Lore trailers.

## Do NOT

- Leave background server/worker processes running
- Hide runtime failures behind relaxed assertions
- Expand into test suite reclassification; TP-010 owns that

---

## Amendments (Added During Execution)
