# Task: TP-005 - TaskSchedule End-to-End Smoke Test

**Created:** 2026-05-31
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Adds operational verification for multiple processes. It is mostly scripts/docs but validates the product path and may expose runtime issues.
**Score:** 4/8 — Blast radius: 1, Pattern novelty: 2, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-005-end-to-end-smoke/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Create a repeatable end-to-end smoke path proving the TaskSchedule MVP: start server, start worker, submit a client task, and observe success/failure through logs or the info API. Prefer a script that can be run locally and a documented manual fallback.

## Dependencies

- **Task:** TP-003 (usable client)
- **Task:** TP-004 (aligned runtime config)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `docs/task-schedule-mvp.md` — MVP acceptance criteria
- `applications/TaskSchedule/app/TaskScheduleServer.hs` — server runtime behavior
- `applications/TaskSchedule/app/TaskScheduleWorker.hs` — worker runtime behavior
- `applications/TaskSchedule/app/TaskScheduleClient.hs` — client runtime behavior
- `lotos/src/Lotos/Zmq/LBS/InfoStorage.hs` — info API endpoints
- `README.md` — current run instructions

## Environment

- **Workspace:** root scripts/docs and `applications/TaskSchedule`
- **Services required:** Local server/worker processes for smoke execution

## File Scope

- `scripts/task-schedule-smoke.sh` (new, if script approach is viable)
- `docs/task-schedule-mvp.md`
- `README.md`
- `applications/TaskSchedule/config/*` (only if smoke-specific sample config is needed)

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] TP-003 and TP-004 completion criteria are satisfied

### Step 1: Design smoke approach

**Plan-review checkpoint** — review process orchestration and cleanup before adding a script.

- [ ] Identify server/worker/client commands from the contract
- [ ] Identify readiness checks and timeout behavior
- [ ] Decide how to clean up spawned processes safely

### Step 2: Implement smoke test/runbook

- [ ] Add `scripts/task-schedule-smoke.sh` or a documented manual fallback if scripting is not viable
- [ ] Submit a simple command task through `ts-client`
- [ ] Query logs or info API to prove task flow reached worker/status reporting
- [ ] Ensure cleanup runs on failure and success

### Step 3: Testing & Verification

**Code review checkpoint** — review the smoke script/runbook and evidence before completion.

- [ ] Build passes: `cabal build all`
- [ ] Smoke script or manual runbook executed locally, or blocker documented with exact failure
- [ ] Verification evidence captured in STATUS.md

### Step 4: Documentation & Delivery

- [ ] README includes concise smoke/run instructions
- [ ] MVP contract marks end-to-end acceptance as verified or lists blockers
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `README.md` — smoke/run instructions
- `docs/task-schedule-mvp.md` — verification status and operational notes

**Check If Affected:**
- `taskplane-tasks/CONTEXT.md` — append follow-up runtime debt if discovered

## Completion Criteria

- [ ] There is a repeatable end-to-end smoke path
- [ ] The smoke path proves client → server → worker → observable status/log path, or documents the exact remaining runtime blocker
- [ ] Builds pass

## Git Commit Convention

Commits happen at step boundaries. All commits for this task MUST include the task ID for traceability.

## Do NOT

- Leave background server/worker processes running
- Hide smoke failures; document exact blockers
- Convert long-running demos into CI tests in this task

---

## Amendments (Added During Execution)
