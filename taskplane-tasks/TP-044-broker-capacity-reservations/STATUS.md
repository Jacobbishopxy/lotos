# TP-044: Add broker-side capacity reservations between heartbeats — Status

**Current Step:** Step 5: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-04
**Review Level:** 3
**Review Counter:** 15
**Iteration:** 2
**Size:** L

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Design reservation model
**Status:** ✅ Complete

- [x] Plan-review checkpoint — decide whether reservations live in worker task map, a new broker map, or adjusted worker snapshots passed to `LoadBalancerAlgo`.
- [x] Define how reservations are created on dispatch and released on worker status/task-status/stale recovery.
- [x] Preserve public scheduler API unless a clearly documented extension is required.
- [x] R001 revision: document concrete reservation state location and scheduler snapshot strategy.
- [x] R001 revision: document event-by-event reservation lifecycle including same-pass, heartbeat, task status, and stale recovery release rules.
- [x] R002 revision: make heartbeat reconciliation conservative so stale heartbeats cannot clear broker-known occupied slots too early.
- [x] R002 revision: define the capacity signal that counts non-terminal broker-known tasks after `TaskProcessing` until terminal status or safe heartbeat reconciliation.

---

### Step 2: Implement reservation accounting
**Status:** ✅ Complete

- [x] Track same-pass and between-heartbeat reservations per worker.
- [x] Prevent repeated scheduler passes from assigning beyond reported capacity while status has not caught up.
- [x] Release reservations when task status reports processing/succeed/fail or when stale-worker recovery reclaims tasks.
- [x] R006 revision: keep unknown-baseline non-terminal occupancy unreconciled until terminal status/stale recovery or preserve the original dispatch baseline when processing updates arrive.

---

### Step 3: Add tests
**Status:** ✅ Complete

- [x] Add fixed-clock or deterministic scheduler/TaskProcessor tests for repeated scheduling before heartbeat update.
- [x] Test reservation release on success/failure/stale recovery.
- [x] Verify multi-worker capacity fairness remains stable.
- [x] R008 revision: add regression coverage showing non-terminal status or stale heartbeat does not release broker-known occupied capacity before terminal status/stale recovery.
- [x] R010 revision: exercise the reservation reconciliation/lifecycle helpers used by TaskProcessor and SocketLayer rather than only manually applying overlay or deleting raw maps.
- [x] R011 revision: route TaskProcessor stale-worker cleanup through the tested shared `releaseWorkerReservations` helper.

---

### Step 4: Testing & Verification
**Status:** ✅ Complete

- [x] Test-review checkpoint — review over-assignment and release coverage.
- [x] Run TaskSchedule scheduler tests, worker frame tests, liveness/retry tests.
- [x] R013 revision: explicitly run `cabal test lotos:test:test-zmq-capacity-reservations` and record pass/fail evidence.
- [x] Run `cabal build all --enable-tests`.
- [x] Run single/multi-worker smoke.

---

### Step 5: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update mdBook architecture/TaskSchedule chapters with heartbeat-vs-reservation behavior.
- [x] Update known risks in `taskplane-tasks/CONTEXT.md`.
- [x] Ensure exactly one final TP commit exists.

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|

---

## Notes / Discoveries

- Plan review R001 suggestion: prefer a broker-owned reservation overlay applied before calling `scheduleTasks` to preserve existing scheduler source compatibility.
- Step 1 design — Reservation state lives in a new broker-owned `TSWorkerReservationsMap` shared through `TaskSchedulerData`, not in the worker status map. `TaskProcessor` records reservations immediately after accepted scheduler dispatches are sent to the socket-layer PAIR so the next scheduler pass sees same-pass/between-heartbeat capacity already consumed. `SocketLayer`/stale recovery remove reservations as lifecycle events prove they no longer represent unobserved capacity.
- Step 1 design — Scheduler input remains `scheduleTasks :: lb -> [(RoutingID, w)] -> [Task t] -> ...`. Before calling `scheduleTasks`, `TaskProcessor` builds reservation-adjusted snapshots: generic worker status values are passed through unchanged by the default compatibility hook, while TaskSchedule `WorkerState` adds broker reservation counts to the waiting/processing side of its existing capacity calculation. This preserves `LoadBalancerAlgo` method semantics and lets existing schedulers remain source-compatible unless they opt into capacity reservation adjustment.
- Step 1 lifecycle (superseded by R002) — dispatch: add one reservation per `(worker, taskId)` after a successful TaskProcessor dispatch send; same scheduler pass still relies on the scheduler's normal per-pass capacity math, while subsequent passes consume these reservations. Worker heartbeat: clear that worker's outstanding reservations because the heartbeat's waiting/processing counts are now the authoritative snapshot. Worker `TaskProcessing`: release the reservation for that task and keep the existing worker task map status updated, so the task is no longer counted as merely unobserved dispatch. Worker `TaskSucceed`/`TaskFailed`: release/delete the reservation; success removes the completed task from broker in-flight tracking, failure follows existing retry/garbage handling. Stale worker recovery: delete all reservations for each recovered stale worker before requeueing/garbaging its tasks.
- Plan review R002 correction: model the overlay as broker-known occupied slots not yet safely reflected in scheduler input. Reservations are not blindly cleared by heartbeat or `TaskProcessing`; non-terminal broker-known task entries (`TaskInit`, `TaskPending`, `TaskProcessing`) continue to consume overlay capacity until terminal status or conservative reconciliation proves the heartbeat snapshot already accounts for at least that many occupied slots.
- Step 1 lifecycle (R002 final): dispatch records a broker-owned occupied slot for the task. Heartbeat reconciliation is conservative: the worker's heartbeat timestamp is updated for liveness, but broker-known non-terminal occupancy is retained unless the implementation can prove the status payload accounts for it; for TaskSchedule the overlay is simply added to `waitingTaskNum`, so even stale heartbeats remain safe. `TaskProcessing` changes the task-map status but does not free capacity; it keeps counting as broker-known occupancy until `TaskSucceed`, `TaskFailed`, or stale recovery. `TaskSucceed` removes the in-flight task/overlay entry and notifies scheduling. `TaskFailed` removes the overlay while following existing retry/garbage handling. Stale-worker recovery removes all overlay entries for the stale worker while requeueing/garbaging its non-succeeded tasks.
- R006 code review: unknown-baseline occupancy markers must never be reconciled as baseline zero; keep them until terminal/stale recovery or carry forward a known dispatch baseline.
- R008 plan review: Step 3 tests must cover both no-release on non-terminal/unsafe heartbeat and release on terminal/stale recovery.
- R010 code review: Step 3 tests must call the shared reconciliation/lifecycle helpers that TaskProcessor and SocketLayer use so regressions in those paths fail tests.
- R011 code review: stale-worker cleanup must call the same shared helper covered by the reservation lifecycle tests.
- R013 plan review: Step 4 must explicitly execute the new `lotos:test:test-zmq-capacity-reservations` suite in addition to compiling it.
- Step 4 test-review checkpoint: coverage includes repeated scheduler overlay consumption, conservative non-terminal/stale heartbeat retention, known/unknown baseline reconciliation, terminal per-task release, stale-worker release via the TaskProcessor helper, TaskSchedule fairness, worker frame compatibility, worker wake/liveness, full test-enabled build, and single/multi-worker smoke gates.
- Step 4 verification: `cabal test TaskSchedule:test:test-scheduler TaskSchedule:test:test-worker-lifecycle lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames lotos:test:test-zmq-worker-wake` PASS (scheduler 10 cases, worker lifecycle 4, worker frames 23, client ACK frames 3, worker wake 2). Fixed a stale test fixture constructor to include the new reservations map before rerun.
- Step 4 verification: `cabal test lotos:test:test-zmq-capacity-reservations` PASS (5 HUnit cases).
- Step 4 verification: `cabal build all --enable-tests` PASS; built lotos library/tests/demos and TaskSchedule libraries/executables/tests with GHC 9.14.1.
- Step 4 verification: `scripts/task-schedule-smoke.sh && scripts/task-schedule-multi-worker-smoke.sh` PASS. Evidence: `.tmp/task-schedule-smoke/task-schedule-smoke-20260604T053128Z-299008/` and `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260604T053218Z-299006/`; single worker received ACK/marker/log evidence, multi-worker ACKed 4 tasks across 2 registered workers with fresh markers and clean `/logs/stats`.
- Step 5 documentation: updated `docs/book/lotos/src/architecture.md`, `docs/book/lotos/src/task-schedule.md`, and affected `docs/task-schedule-mvp.md` to describe broker reservation overlay behavior between heartbeats.
- Step 5 context update: added TP-044 reservation summary plus a future-work risk for intentionally conservative unknown-baseline reservation reconciliation in `taskplane-tasks/CONTEXT.md`.
- Step 5 documentation verification: `make book-build` PASS; mdBook HTML written under `docs/book/lotos/book`.
- Step 5 delivery: verified `git rev-list --count 49917bb..HEAD` returned `1` after squashing TP-044 work into a single final TP commit.

| 2026-06-04 04:22 | Task started | Runtime V2 lane-runner execution |
| 2026-06-04 04:22 | Step 0 started | Preflight |
| 2026-06-04 04:23 | Exit intercept reprompt | Supervisor provided instructions (406 chars) — reprompting worker |
| 2026-06-04 04:26 | Review R001 | plan Step 1: REVISE |
| 2026-06-04 04:32 | Review R002 | plan Step 1: REVISE |
| 2026-06-04 04:36 | Review R004 | code Step 1: APPROVE |
| 2026-06-04 04:40 | Review R005 | plan Step 2: APPROVE |
| 2026-06-04 04:52 | Review R006 | code Step 2: REVISE |
| 2026-06-04 04:58 | Review R007 | code Step 2: APPROVE |
| 2026-06-04 05:00 | Review R008 | plan Step 3: REVISE |
| 2026-06-04 05:01 | Review R009 | plan Step 3: APPROVE |
| 2026-06-04 05:09 | Review R010 | code Step 3: REVISE |
| 2026-06-04 05:19 | Review R011 | code Step 3: REVISE |
| 2026-06-04 05:22 | Review R012 | code Step 3: APPROVE |
| 2026-06-04 05:25 | Review R013 | plan Step 4: REVISE |
| 2026-06-04 05:26 | Review R014 | plan Step 4: APPROVE |
| 2026-06-04 05:35 | Review R015 | code Step 4: UNAVAILABLE (reviewer produced no output); proceeding with recorded verification evidence |

| 2026-06-04 05:28 | Worker iter 1 | done in 3961s, tools: 220 |
| 2026-06-04 05:43 | Worker iter 2 | done in 893s, tools: 72 |
| 2026-06-04 05:43 | Task complete | .DONE created |