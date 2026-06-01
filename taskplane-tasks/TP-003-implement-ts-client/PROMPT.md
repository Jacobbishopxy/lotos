# Task: TP-003 - Implement TaskSchedule Client Submission

**Created:** 2026-05-31
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Implements the missing user-facing client path and touches executable/library code. It should follow existing config and ZMQ patterns without changing core protocol semantics.
**Score:** 4/8 — Blast radius: 1, Pattern novelty: 1, Security: 0, Reversibility: 2

## Canonical Task Folder

```
taskplane-tasks/TP-003-implement-ts-client/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Turn `ts-client` from a placeholder into a usable CLI that submits `ClientTask` work to the load balancer according to the MVP runtime contract. The client should support a simple command submission path and a JSON task file path while reusing existing `ClientServiceConfig`, `mkClientService`, and `sendTaskRequest` patterns.

## Dependencies

- **Task:** TP-002 (runtime contract must be complete)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `docs/task-schedule-mvp.md` — canonical runtime contract from TP-002
- `applications/TaskSchedule/app/TaskScheduleClient.hs` — placeholder executable
- `applications/TaskSchedule/src/Client.hs` — current task file helper
- `applications/TaskSchedule/src/Adt.hs` — `ClientTask` shape and ZMQ instances
- `lotos/src/Lotos/Zmq/LBC.hs` — client service API
- `lotos/src/Lotos/Zmq/Config.hs` — `ClientServiceConfig` and reader

## Environment

- **Workspace:** `applications/TaskSchedule`
- **Services required:** None for build/unit checks; server required only for optional manual smoke

## File Scope

- `applications/TaskSchedule/app/TaskScheduleClient.hs`
- `applications/TaskSchedule/src/Client.hs`
- `applications/TaskSchedule/TaskSchedule.cabal` (only if needed for dependencies/options)
- `README.md` or `docs/task-schedule-mvp.md` (only if client UX changes from TP-002 contract)

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] TP-002 contract is complete and readable

### Step 1: Design the client path

**Plan-review checkpoint** — review CLI/config behavior before editing.

- [ ] Confirm command-line UX from `docs/task-schedule-mvp.md`
- [ ] Identify whether existing dependencies are sufficient; do not add dependencies without necessity
- [ ] Decide error messages and exit behavior for missing/invalid args or config

### Step 2: Implement `ts-client`

- [ ] Parse supported inputs from CLI according to contract
- [ ] Build/read `ClientServiceConfig` according to contract defaults
- [ ] Submit `Task ClientTask` using `mkClientService` and `sendTaskRequest`
- [ ] Print a useful acknowledgement or failure message

**Artifacts:**
- `applications/TaskSchedule/app/TaskScheduleClient.hs` (modified)
- `applications/TaskSchedule/src/Client.hs` (modified if needed)

### Step 3: Testing & Verification

**Code review checkpoint** — review the final client changes before completion.

- [ ] Build passes: `cabal build TaskSchedule:exe:ts-client`
- [ ] Build all passes: `cabal build all`
- [ ] If no server is running, document that only build/argument-level behavior was verified here

### Step 4: Documentation & Delivery

- [ ] Update docs if actual client behavior differs from TP-002 contract
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `docs/task-schedule-mvp.md` — only if implementation requires contract adjustment

**Check If Affected:**
- `README.md` — client command examples if concise

## Completion Criteria

- [ ] `ts-client` is no longer a placeholder
- [ ] Client can construct and submit a task using existing ZMQ client APIs
- [ ] Relevant builds pass

## Git Commit Convention

Commits happen at step boundaries. All commits for this task MUST include the task ID for traceability.

## Do NOT

- Change core ZMQ protocol frame ordering
- Add dependencies unless unavoidable and documented
- Implement server/worker config changes beyond what client requires

---

## Amendments (Added During Execution)
