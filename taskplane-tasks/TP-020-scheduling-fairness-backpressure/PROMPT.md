# Task: TP-020 - Scheduling Fairness and Backpressure

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Hardens scheduling behavior across multiple workers and task bursts. It touches TaskSchedule scheduling policy/tests/smoke and may expose core scheduler assumptions.
**Score:** 5/8 — Blast radius: 2, Pattern novelty: 1, Security: 0, Reversibility: 2

## Canonical Task Folder

```
taskplane-tasks/TP-020-scheduling-fairness-backpressure/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Verify and improve scheduling fairness/backpressure so TaskSchedule does not over-assign tasks to workers beyond their reported/derived capacity and distributes bursts reasonably across available workers. Build on the multi-worker smoke from TP-017 and worker recovery semantics from TP-019.

## Dependencies

- **Task:** TP-019 (worker liveness/disconnect recovery should be complete before hardening scheduling fairness)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `README.md` — current smoke and scheduling notes
- `docs/task-schedule-mvp.md` — current demo contract
- `docs/build-your-own-scheduler.md` — scheduler adopter guidance
- `applications/TaskSchedule/src/Server.hs` — current `SimpleServer` scheduling policy
- `applications/TaskSchedule/src/Adt.hs` — `WorkerState` waiting/processing counts
- `applications/TaskSchedule/app/TaskScheduleWorker.hs` — worker parallelism/config
- `applications/TaskSchedule/config/*.json` — sample configs
- `scripts/task-schedule-multi-worker-smoke.sh` — current multi-worker proof
- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs` — queue pulling/scheduling handoff
- `lotos/src/Lotos/Zmq/LBW.hs` — worker queue/parallel task info
- `applications/TaskSchedule/test/*` and `lotos/test/*` — bounded test style

## Environment

- **Workspace:** TaskSchedule scheduler/tests/smoke/docs and minimal core scheduling if proven necessary
- **Services required:** Existing single-worker and multi-worker smoke scripts for final verification

## File Scope

- `applications/TaskSchedule/src/Server.hs`
- `applications/TaskSchedule/src/Adt.hs`
- `applications/TaskSchedule/test/*`
- `applications/TaskSchedule/TaskSchedule.cabal` (only if adding tests)
- `scripts/task-schedule-multi-worker-smoke.sh`
- `scripts/task-schedule-smoke.sh` (only if shared helper changes)
- `docs/task-schedule-mvp.md`
- `docs/build-your-own-scheduler.md`
- `README.md`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-020-scheduling-fairness-backpressure/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] TP-019 completion status and current multi-worker smoke are understood

### Step 1: Define fairness/backpressure contract

**Plan-review checkpoint** — review scheduling contract and test strategy before implementation.

- [ ] Define what “fair enough” means for `SimpleServer` with multiple workers and task bursts
- [ ] Define worker capacity/backpressure constraints using available state (`processingTaskNum`, `waitingTaskNum`, and/or config-derived limits)
- [ ] Identify bounded unit tests and smoke assertions
- [ ] Define follow-up debt if precise production scheduling is out of scope

### Step 2: Implement tests and scheduling/backpressure improvements

- [ ] Add bounded scheduler tests for multi-worker distribution and capacity/backpressure behavior
- [ ] Patch `SimpleServer` scheduling minimally if tests reveal over-assignment or unfairness
- [ ] Extend multi-worker smoke assertions only where deterministic enough
- [ ] Preserve retry/liveness and current smoke behavior

### Step 3: Testing & Verification

**Code review checkpoint** — review scheduling changes and evidence before completion.

- [ ] `cabal build all --enable-tests` passes
- [ ] `cabal test all` passes
- [ ] `scripts/task-schedule-smoke.sh` passes
- [ ] `scripts/task-schedule-multi-worker-smoke.sh` passes
- [ ] Scheduler fairness/backpressure tests pass

### Step 4: Documentation & Delivery

- [ ] README/docs describe scheduling/backpressure behavior if user-facing
- [ ] Context debt updated with resolved/new scheduler debt
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `taskplane-tasks/CONTEXT.md` — scheduler/backpressure debt status

**Check If Affected:**
- `README.md`
- `docs/task-schedule-mvp.md`
- `docs/build-your-own-scheduler.md`

## Completion Criteria

- [ ] Bounded tests cover multi-worker fairness/backpressure expectations
- [ ] Multi-worker smoke remains green
- [ ] Scheduling behavior is documented honestly
- [ ] Build and regression tests pass

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-020` and Lore trailers.

## Do NOT

- Over-engineer a production scheduler beyond TaskSchedule's demo scope
- Hide nondeterministic scheduling by weakening assertions too far
- Add dependencies
- Break existing single-worker or multi-worker smoke paths

---

## Amendments (Added During Execution)
