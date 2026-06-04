# TP-050: Public API/readme polish for first users — Status

**Current Step:** Step 5: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-04
**Review Level:** 1
**Review Counter:** 4
**Iteration:** 1
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied

---

### Step 1: Audit first-user flow
**Status:** ✅ Complete

- [x] README/API unclear paths identified
- [x] Scheduler guide checked against current APIs
- [x] Logging/migration wording checked
- [x] Facade exports reviewed if docs need names

---

### Step 2: Polish quickstart and API docs
**Status:** ✅ Complete

- [x] Commands clarified
- [x] Minimal setup/config clarified
- [x] Scheduler extension points clarified
- [x] Logging reliability wording corrected
- [x] Facade export changes made only if needed

---

### Step 3: Align compatibility and migration notes
**Status:** ✅ Complete

- [x] Legacy logging and worker-state compatibility cross-linked
- [x] Protocol versioning guidance linked
- [x] TaskSchedule capacity/smoke docs aligned

---

### Step 4: Testing & Verification
**Status:** ✅ Complete

- [x] `make book-build` passes
- [x] `make ci-check` or equivalent passes
- [x] `cabal build all --enable-tests` passes if Haskell changed
- [x] All failures fixed

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
| R001 | plan | Step 1 | APPROVE | `.reviews/R001-plan-step1.md` |
| R002 | plan | Step 2 | APPROVE | `.reviews/R002-plan-step2.md` |
| R003 | plan | Step 3 | APPROVE | `.reviews/R003-plan-step3.md` |
| R004 | plan | Step 4 | APPROVE | `.reviews/R004-plan-step4.md` |

---

## Notes

| 2026-06-04 13:51 | Task started | Runtime V2 lane-runner execution |
| 2026-06-04 13:51 | Step 0 started | Preflight |
| 2026-06-04 | Audit | README/API mostly current; polish targets are first-user command sequencing, config filename callouts, public facade setup examples, and avoiding stale `cabal test all` guidance. |
| 2026-06-04 | Audit | Scheduler guide needs current `LoadBalancerAlgo` optional capacity hooks (`applyCapacityReservations`, `workerOccupiedSlots`) plus TP-049 gate wording instead of recommending `cabal test all`. |
| 2026-06-04 | Audit | Logging/migration wording consistently rejects exactly-once; docs still need tighter cross-links between public API, compatibility, logging redesign, and protocol versioning pages. |
| 2026-06-04 | Audit | `Lotos.Zmq` facade already exports the documented config readers, service constructors, `LoadBalancerAlgo(..)` capacity hooks, worker APIs, `LogIngestConfig`, and reservation helpers; no Haskell facade change currently needed. |
| 2026-06-04 | Step 2 | No facade export change made because the polished docs only reference names already exported by `Lotos.Zmq`. |
| 2026-06-04 | Verification | `make ci-check` passed and included `cabal build all --enable-tests`; no Haskell files were changed. |
| 2026-06-04 | Delivery | Reviewed affected docs: compatibility and TaskSchedule were updated; introduction and taskplane context needed no content changes. |
| 2026-06-04 | Discoveries | No new technical debt discovered beyond the documentation polish completed in this task. |
| 2026-06-04 13:53 | Review R001 | plan Step 1: APPROVE |
| 2026-06-04 13:55 | Review R002 | plan Step 2: APPROVE |
| 2026-06-04 13:59 | Review R003 | plan Step 3: APPROVE |
| 2026-06-04 14:02 | Review R004 | plan Step 4: APPROVE |

| 2026-06-04 14:07 | Worker iter 1 | done in 963s, tools: 105 |
| 2026-06-04 14:07 | Task complete | .DONE created |