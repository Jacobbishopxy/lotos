# Task: TP-017 - Multi-Worker Scheduling Smoke

**Created:** 2026-06-01
**Size:** M

## Review Level: 2 (Plan and Code)

**Assessment:** Adds an integration smoke that proves the load balancer handles multiple workers and multiple tasks. It touches smoke tooling/config/docs and may reveal scheduling/runtime defects.
**Score:** 5/8 — Blast radius: 2, Pattern novelty: 2, Security: 0, Reversibility: 1

## Canonical Task Folder

```
taskplane-tasks/TP-017-multi-worker-scheduling-smoke/
├── PROMPT.md
├── STATUS.md
├── .reviews/
└── .DONE
```

## Mission

Prove TaskSchedule operates with multiple workers, not just a single happy-path worker. Add a bounded smoke path that starts two or more workers with distinct IDs, submits multiple tasks, and verifies worker stats/logs/task outcomes per worker without leaving processes running.

## Dependencies

- **Task:** TP-016 (API boundary cleanup should be complete before adding more smoke/tooling)

## Context to Read First

**Tier 2 (area context):**
- `taskplane-tasks/CONTEXT.md`

**Tier 3 (load only if needed):**
- `docs/task-schedule-mvp.md` — current single-worker smoke contract
- `scripts/task-schedule-smoke.sh` — existing smoke helper and cleanup patterns
- `applications/TaskSchedule/config/*.json` — sample configs
- `applications/TaskSchedule/app/TaskScheduleWorker.hs` — worker config/identity behavior
- `applications/TaskSchedule/src/Server.hs` — load-based scheduler
- `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs` — task scheduling loop
- `lotos/src/Lotos/Zmq/LBS/InfoStorage.hs` — status/log observability
- `README.md` — smoke/run documentation

## Environment

- **Workspace:** smoke scripts/config/docs and any minimal runtime fixes found by smoke
- **Services required:** Local server and multiple worker/client processes started by smoke script

## File Scope

- `scripts/*smoke*.sh`
- `applications/TaskSchedule/config/*`
- `applications/TaskSchedule/app/TaskScheduleWorker.hs` (only if distinct worker IDs/configs expose a defect)
- `applications/TaskSchedule/src/Server.hs` (only if scheduling defect is proven)
- `docs/task-schedule-mvp.md`
- `README.md`
- `taskplane-tasks/CONTEXT.md`
- `taskplane-tasks/TP-017-multi-worker-scheduling-smoke/*`

## Steps

### Step 0: Preflight

- [ ] Required files and paths exist
- [ ] TP-016 complete and single-worker smoke is green

### Step 1: Design multi-worker smoke

**Plan-review checkpoint** — review process orchestration and pass criteria before implementation.

- [ ] Decide whether to extend `task-schedule-smoke.sh` with a mode or add a separate multi-worker helper
- [ ] Define distinct worker configs/IDs and expected worker_stats/logging evidence
- [ ] Define task count, timeout, cleanup, and pass/fail criteria

### Step 2: Implement multi-worker smoke path

- [ ] Start server plus at least two workers with distinct IDs/configs
- [ ] Submit multiple task JSON files with fresh markers
- [ ] Verify workers appear in `/worker_stats`
- [ ] Verify submitted tasks complete and logs/markers are attributable to current run
- [ ] Clean up all spawned processes safely

### Step 3: Testing & Verification

**Code review checkpoint** — review smoke script and evidence before completion.

- [ ] `cabal build all --enable-tests` passes
- [ ] `cabal test all` passes
- [ ] Existing single-worker `scripts/task-schedule-smoke.sh` passes
- [ ] New multi-worker smoke passes or exact runtime blocker is documented

### Step 4: Documentation & Delivery

- [ ] README documents multi-worker smoke command if added
- [ ] MVP docs describe multi-worker verification status
- [ ] Context debt updated with any scheduling findings
- [ ] Discoveries logged in STATUS.md

## Documentation Requirements

**Must Update:**
- `README.md` — multi-worker smoke command/status
- `docs/task-schedule-mvp.md` — multi-worker verification status
- `taskplane-tasks/CONTEXT.md` — scheduling debt if discovered

**Check If Affected:**
- `applications/TaskSchedule/config/*` — sample config docs match actual files

## Completion Criteria

- [ ] Multi-worker smoke path exists and is bounded
- [ ] At least two distinct workers are visible in worker stats during smoke
- [ ] Multiple tasks complete with current-run marker/log evidence
- [ ] Build, regression tests, and single-worker smoke remain green

## Git Commit Convention

Final history must contain exactly one commit for this TP. Temporary checkpoint commits must be squashed before handoff. The final commit message must include `TP-017` and Lore trailers.

## Do NOT

- Leave background server/worker processes running
- Hide scheduling defects by weakening assertions
- Convert smoke scripts into unbounded Cabal tests

---

## Amendments (Added During Execution)
