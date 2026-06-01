# TP-020: Scheduling Fairness and Backpressure — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-01
**Review Level:** 2
**Review Counter:** 4
**Iteration:** 4
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] TP-019 completion status and current multi-worker smoke are understood

---

### Step 1: Define fairness/backpressure contract
**Status:** ✅ Complete

- [x] Fairness contract defined

Contract notes:
- Fairness: `SimpleServer` should distribute a burst across the currently available worker snapshot by assigning at most one new task to each eligible worker per scheduler pass, preferring the lowest CPU/memory load score and using stable snapshot order as the tie-breaker. With two equal idle workers and four queued tasks, one task should be assigned to each worker and the other two should remain queued for a later pass rather than all four going to the first worker.
- Backpressure/capacity: `WorkerState` exposes only `processingTaskNum` and `waitingTaskNum`, not each worker's `parallelTasksNo`, so the demo-safe derived capacity is one newly assigned task only when both counters are zero. Workers reporting any processing or queued work are saturated for this scheduler pass; their tasks should stay in `tasksLeft` and be re-enqueued by `TaskProcessor`.
- Bounded proof: add a TaskSchedule unit test suite that invokes `scheduleTasks` with fixed `WorkerState` fixtures to assert (1) equal idle workers split a burst one-per-worker and leave overflow queued, (2) busy/waiting workers receive no new tasks while idle workers do, and (3) all-saturated workers return all tasks as `tasksLeft`. Keep smoke assertions at per-worker current-run evidence unless a deterministic distribution check is available from broker snapshots/logs.
- Debt boundary: do not add broker-wide worker capacity config or a production scheduler in TP-020. If users need full `parallelTasksNo`-aware capacity, document/log that as future work because current worker heartbeats do not report the configured maximum.
- [x] Capacity/backpressure constraints defined
- [x] Bounded tests/smoke assertions identified
- [x] Follow-up debt boundary defined if needed

---

### Step 2: Implement tests and scheduling/backpressure improvements
**Status:** ✅ Complete

- [x] Scheduler tests added
- [x] `SimpleServer` scheduling patched minimally if needed
- [x] Multi-worker smoke assertions extended if deterministic
- [x] Existing retry/liveness/smoke behavior preserved

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] `cabal build all --enable-tests` passes
- [x] `cabal test all` passes
- [x] Single-worker smoke passes
- [x] Multi-worker smoke passes
- [x] Fairness/backpressure tests pass

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] README/docs updated if needed
- [x] Context debt updated
- [x] Discoveries logged

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | Plan | 1 | APPROVE | `.reviews/R001-plan-step1.md` |
| R002 | Plan | 2 | APPROVE | `.reviews/R002-plan-step2.md` |
| R003 | Code | 2 | APPROVE | `.reviews/R003-code-step2.md` |
| R004 | Plan | 3 | APPROVE | `.reviews/R004-plan-step3.md` |

---

## Discoveries

- Preflight: TP-019 is marked complete with `cabal build all --enable-tests`, `cabal test all`, single-worker smoke, multi-worker smoke, and stale-worker recovery tests passing; current multi-worker smoke runs 2 workers/4 tasks by default, forces `parallelTasksNo: 1`, and only asserts each worker processed at least one current-run task plus fresh markers/logging rather than exact distribution.
- Step 2 smoke assertion review: no exact distribution assertion was added to `scripts/task-schedule-multi-worker-smoke.sh`; scheduler fairness/backpressure is deterministic at the `scheduleTasks` snapshot boundary and is covered by `TaskSchedule:test:test-scheduler`, while the multi-worker smoke remains bounded to per-worker current-run execution, fresh markers, logging, and no garbage.
- Step 4 documentation: user-facing docs now describe `SimpleServer` as a conservative demo scheduler that assigns one new task per idle worker per pass, defers overflow, and treats `parallelTasksNo`-aware capacity as future work because current `WorkerState` heartbeats do not report configured capacity.

---

## Execution Log

| 2026-06-01 14:28 | Task started | Runtime V2 lane-runner execution |
| 2026-06-01 14:28 | Step 0 started | Preflight |
| 2026-06-01 14:37 | Worker iter 1 | done in 541s, tools: 49 |
| 2026-06-01 14:54 | Worker iter 2 | done in 1046s, tools: 68 |
| 2026-06-01 14:55 | Exit intercept reprompt | Supervisor provided instructions (741 chars) — reprompting worker |
| 2026-06-01 14:55 | Worker iter 3 | done in 49s, tools: 5 |
| 2026-06-01 14:55 | Step 4 started | Documentation & Delivery |
| 2026-06-01 15:00 | Worker iter 4 | done in 287s, tools: 39 |
| 2026-06-01 15:00 | Task complete | .DONE created |
---

## Blockers

---

## Notes
| 2026-06-01 14:34 | Review R001 | plan Step 1: APPROVE; suggestion: consider adding a load-score preference scheduler test |
| 2026-06-01 14:36 | Review R002 | plan Step 2: APPROVE |
| 2026-06-01 14:47 | Review R003 | code Step 2: APPROVE |
| 2026-06-01 14:49 | Review R004 | plan Step 3: APPROVE |
