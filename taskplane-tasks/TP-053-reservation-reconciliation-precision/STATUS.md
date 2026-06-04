# TP-053: Reservation reconciliation precision — Status

**Current Step:** Step 5: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-04
**Review Level:** 2
**Review Counter:** 8
**Iteration:** 1
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied

---

### Step 1: Assess current state and design
**Status:** ✅ Complete

- [x] Reservation lifecycle code/tests/docs inventoried with conservative-retention cases identified
- [x] Reconciliation design captured using existing task status/heartbeat evidence without widening public scheduler APIs
- [x] Targeted baseline verification run or explicitly documented as not useful

---

### Step 2: Implement focused changes
**Status:** ✅ Complete

- [x] Non-terminal reservation refresh only updates existing broker reservations and does not recreate released reservations
- [x] Regression coverage added for no-resurrection after safe heartbeat reconciliation while preserving unsafe-heartbeat retention behavior
- [x] Targeted reservation and scheduler tests pass after implementation

---

### Step 3: Documentation alignment
**Status:** ✅ Complete

- [x] Must-update docs modified
- [x] Affected docs reviewed
- [x] Follow-up gaps logged if found

---

### Step 4: Testing & Verification
**Status:** ✅ Complete

- [x] `cabal test lotos:test:test-zmq-capacity-reservations` passes
- [x] `cabal test TaskSchedule:test:test-scheduler` passes
- [x] `make ci-check` passes
- [x] `make book-build` passes
- [x] All failures fixed or no failures encountered

---

### Step 5: Documentation & Delivery
**Status:** ✅ Complete

- [x] "Must Update" docs modified
- [x] "Check If Affected" docs reviewed
- [x] Discoveries logged

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | Plan | Step 1 | APPROVE | `.reviews/R001-plan-step1.md` |
| R002 | Code | Step 1 | APPROVE | `.reviews/R002-code-step1.md` |
| R003 | Plan | Step 2 | APPROVE | `.reviews/R003-plan-step2.md` |
| R004 | Code | Step 2 | APPROVE | `.reviews/R004-code-step2.md` |
| R005 | Plan | Step 3 | APPROVE | `.reviews/R005-plan-step3.md` |
| R006 | Code | Step 3 | APPROVE | `.reviews/R006-code-step3.md` |
| R007 | Plan | Step 4 | APPROVE | `.reviews/R007-plan-step4.md` |
| R008 | Code | Step 4 | APPROVE | `.reviews/R008-code-step4.md` |

---

## Notes

| 2026-06-04 15:40 | Task started | Runtime V2 lane-runner execution |
| 2026-06-04 15:40 | Step 0 started | Preflight |
| 2026-06-04 | Inventory | Reservation state is kept in `CapacityReservations`; dispatch records baseline heartbeat occupancy in TaskProcessor; SocketLayer releases on terminal statuses and refreshes non-terminal TaskPending/TaskProcessing. Existing conservative cases: unknown baselines never reconcile, known baselines release only after occupied slots exceed dispatch baseline, and TaskSchedule tests prove stale heartbeat + non-terminal evidence still blocks over-assignment. |
| 2026-06-04 | Design | Preserve `LoadBalancerAlgo` and protocol frames. Treat `refreshNonTerminalReservation` as a refresh of an existing broker reservation only: if heartbeat reconciliation already removed the task reservation, a later TaskPending/TaskProcessing frame must update the worker task status but must not recreate an unknown-baseline reservation. Retain existing unsafe-heartbeat behavior for active reservations and add regression coverage for both retain-before-safe-heartbeat and no-resurrection-after-safe-heartbeat. |
| 2026-06-04 | Baseline verification | `cabal test lotos:test:test-zmq-capacity-reservations TaskSchedule:test:test-scheduler` PASS before source edits (5 reservation cases, 11 scheduler cases). |
| 2026-06-04 | Safety cases | Preserve conservative retention for unknown-baseline reservations and stale/unsafe heartbeats; release known-baseline reservations only when heartbeat occupancy already accounts for them; release terminal statuses and stale workers through existing lifecycle helpers; make duplicate/late non-terminal task-status refreshes no-op once heartbeat reconciliation has already removed the reservation. |
| 2026-06-04 | Step 2 implementation | Changed `refreshNonTerminalReservation` to re-append only an existing reservation and no-op when safe reconciliation has already deleted the task reservation. |
| 2026-06-04 | Step 2 tests | Updated `lotos/test/ZmqCapacityReservations.hs` to prove non-terminal refresh still retains through unsafe heartbeat evidence and that a late non-terminal refresh does not recreate a reservation after safe heartbeat reconciliation removed it. |
| 2026-06-04 | Step 2 verification | `cabal test lotos:test:test-zmq-capacity-reservations TaskSchedule:test:test-scheduler` PASS after implementation (6 reservation cases, 11 scheduler cases). |
| 2026-06-04 | Step 3 docs | Updated `docs/book/lotos/src/runtime-failures.md` and `docs/book/lotos/src/task-schedule.md` to document safe heartbeat release, late/duplicate non-terminal no-resurrection, and conservative retention for unsafe evidence. |
| 2026-06-04 | Step 3 affected-doc review | Updated `docs/book/lotos/src/architecture.md` for the same reservation lifecycle boundary and `taskplane-tasks/CONTEXT.md` to close/refine the TP-053 debt. Reviewed `README.md` and `docs/book/lotos/src/SUMMARY.md`; no top-level command/release guidance or new mdBook page entry changed. |
| 2026-06-04 | Step 3 follow-up | Logged remaining unknown-baseline/causal-ack reservation precision as future work in `taskplane-tasks/CONTEXT.md`; it remains conservative by design because TP-053 did not add protocol frames or scheduler API hooks. |
| 2026-06-04 | Step 4 verification | `cabal test lotos:test:test-zmq-capacity-reservations` PASS (6 HUnit cases). |
| 2026-06-04 | Step 4 verification | `cabal test TaskSchedule:test:test-scheduler` PASS (11 HUnit cases). |
| 2026-06-04 | Step 4 verification | `make ci-check` PASS; built all components/tests/demos with tests enabled, ran the bounded regression target list including reservation/scheduler suites, and built the mdBook. |
| 2026-06-04 | Step 4 verification | `make book-build` PASS; mdBook HTML generated under `docs/book/lotos/book` (generated output not tracked). |
| 2026-06-04 | Step 4 failures | No verification failures encountered; warnings/log messages observed during tests were expected test-path diagnostics and all suites exited PASS. |
| 2026-06-04 | Step 4 cleanup | Removed generated `docs/book/lotos/book/` after book verification so it is not left untracked or accidentally committed. |
| 2026-06-04 | Step 5 delivery docs | Verified Must Update docs `docs/book/lotos/src/runtime-failures.md` and `docs/book/lotos/src/task-schedule.md` contain the safe-heartbeat release and late non-terminal no-resurrection behavior. |
| 2026-06-04 | Step 5 affected docs | Verified `taskplane-tasks/CONTEXT.md` has the TP-053 closure/refined follow-up, `docs/book/lotos/src/architecture.md` was aligned, `README.md` needed no top-level guidance change, and `docs/book/lotos/src/SUMMARY.md` needed no new page entry. |
| 2026-06-04 | Step 5 discoveries | STATUS and `taskplane-tasks/CONTEXT.md` both record that unknown-baseline schedulers still retain reservations until terminal/stale recovery; causal acknowledgement precision is logged as future work. |
| 2026-06-04 15:44 | Review R001 | plan Step 1: APPROVE |
| 2026-06-04 15:53 | Review R002 | code Step 1: APPROVE |
| 2026-06-04 15:55 | Review R003 | plan Step 2: APPROVE |
| 2026-06-04 16:00 | Review R004 | code Step 2: APPROVE |
| 2026-06-04 16:02 | Review R005 | plan Step 3: APPROVE |
| 2026-06-04 16:07 | Review R006 | code Step 3: APPROVE |
| 2026-06-04 16:08 | Review R007 | plan Step 4: APPROVE |
| 2026-06-04 16:14 | Review R008 | code Step 4: APPROVE |

| 2026-06-04 16:18 | Worker iter 1 | done in 2240s, tools: 152 |
| 2026-06-04 16:18 | Task complete | .DONE created |