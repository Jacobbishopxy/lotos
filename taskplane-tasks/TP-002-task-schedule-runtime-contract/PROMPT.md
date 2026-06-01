# Task: TP-002 - TaskSchedule Runtime Contract

**Created:** 2026-05-31
**Size:** S

## Review Level: 1 (Plan Only)

**Assessment:** Defines the MVP operating contract before implementation. Low code blast radius, but it sets decisions that downstream implementation depends on.
**Score:** 2/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 0

## Canonical Task Folder

```
taskplane-tasks/TP-002-task-schedule-runtime-contract/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Define the minimum viable runtime contract for `applications/TaskSchedule`: how a user starts server/worker/client, how addresses/config are chosen, how a task is submitted, and what observable result proves the demo works end-to-end. This task creates the product-facing contract that TP-003 through TP-006 must implement.

## Dependencies

- **None**

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `README.md` — current project documentation and known caveats
- `applications/TaskSchedule/app/TaskScheduleServer.hs` — current server defaults
- `applications/TaskSchedule/app/TaskScheduleWorker.hs` — current worker defaults
- `applications/TaskSchedule/app/TaskScheduleClient.hs` — current client placeholder
- `applications/TaskSchedule/src/Client.hs` — current task loading helper
- `lotos/src/Lotos/Zmq/Config.hs` — existing JSON config readers and service config types

## Environment

- **Workspace:** `applications/TaskSchedule`, `docs`, root docs
- **Services required:** None

## File Scope

- `docs/task-schedule-mvp.md` (new)
- `README.md` (modified if a short link/summary is useful)
- `taskplane-tasks/CONTEXT.md` (append discoveries only if relevant)

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] Dependencies satisfied

### Step 1: Define the contract

**Plan-review checkpoint** — get review on the proposed runtime contract before documenting it as the downstream source of truth.

- [ ] Inspect current TaskSchedule server/worker/client entry points and config types
- [ ] Decide the MVP UX: config file defaults, optional CLI arguments, task JSON shape, and expected info API checks
- [ ] Document known non-goals and risks without expanding implementation scope

**Artifacts:**
- `docs/task-schedule-mvp.md` (new)

### Step 2: Documentation & handoff

- [ ] Add a concise README pointer to the MVP contract if useful
- [ ] Ensure TP-003 through TP-006 can use `docs/task-schedule-mvp.md` as their contract
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `docs/task-schedule-mvp.md` — MVP runtime contract and acceptance criteria

**Check If Affected:**
- `README.md` — link to the MVP contract if it improves discoverability

## Completion Criteria

- [ ] Runtime contract exists and covers server, worker, client, observability, and verification
- [ ] Downstream implementation tasks have clear acceptance criteria
- [ ] Documentation updated

## Git Commit Convention

Commits happen at step boundaries. All commits for this task MUST include the task ID for traceability.

## Do NOT

- Implement server/worker/client changes in this task
- Expand task scope beyond the MVP contract
- Modify framework/standards docs without explicit user approval

---

## Amendments (Added During Execution)
