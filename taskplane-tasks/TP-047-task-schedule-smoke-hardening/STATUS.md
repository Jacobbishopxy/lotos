# TP-047: End-to-end TaskSchedule smoke hardening — Status

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

### Step 1: Characterize current smoke assertions
**Status:** ✅ Complete

- [x] Current proof points and flake-prone waits identified
- [x] Missing capacity/reservation/runtime-stat checks identified
- [x] Existing fresh-marker/per-worker evidence preserved
- [x] Shell syntax checks pass

---

### Step 2: Harden deterministic runtime evidence
**Status:** ✅ Complete

- [x] Bounded retry helpers improved or reused
- [x] `/info.runtimeQueueStats` validated
- [x] `/logs/stats` validated as LogIngest accounting
- [x] Multi-worker capacity/reservation behavior validated
- [x] Single-worker smoke script passes
- [x] Multi-worker smoke script passes

---

### Step 3: Document smoke gates for operators
**Status:** ✅ Complete

- [x] Verification docs updated
- [x] Operations docs updated
- [x] README reviewed/updated if affected

---

### Step 4: Testing & Verification
**Status:** ✅ Complete

- [x] `cabal build all --enable-tests` passes
- [x] `scripts/task-schedule-smoke.sh` passes
- [x] `scripts/task-schedule-multi-worker-smoke.sh` passes
- [x] `make book-build` passes
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
| R001 | plan | 1 | APPROVE | .reviews/R001-plan-step1.md |
| R002 | code | 1 | APPROVE | .reviews/R002-code-step1.md |
| R003 | plan | 2 | APPROVE | .reviews/R003-plan-step2.md |
| R004 | code | 2 | APPROVE | .reviews/R004-code-step2.md |
| R005 | plan | 3 | APPROVE | .reviews/R005-plan-step3.md |
| R006 | code | 3 | APPROVE | .reviews/R006-code-step3.md |
| R007 | plan | 4 | APPROVE | .reviews/R007-plan-step4.md |
| R008 | code | 4 | APPROVE | .reviews/R008-code-step4.md |

---

## Notes

| 2026-06-04 12:16 | Task started | Runtime V2 lane-runner execution |
| 2026-06-04 12:16 | Step 0 started | Preflight |
| 2026-06-04 | Step 1 characterization | Current smoke proof points: single-worker checks server/worker readiness, client ACK exit, fresh marker, per-worker `/logs/worker` stdout/result with ExitSuccess, clean `/logs/stats`, final snapshots, and no current-run garbage. Multi-worker adds generated configs, all clients ACK, all workers registered, per-worker stdio evidence, fresh marker per task, `/logs/worker` evidence per worker, clean `/logs/stats`, and no garbage. Flake-prone waits are repeated hand-written `sleep 1` polling loops for HTTP endpoints/log stats/markers and grep-only JSON assertions with no diagnostic of missing fields. |
| 2026-06-04 | Step 1 missing checks | Missing/weak smoke gates: no assertion that `/info` exposes `runtimeQueueStats` entries/fields; `/logs/stats` is treated as the only runtime accounting rather than explicitly separated from handoff stats; single-worker does not prove worker configured capacity (`taskCapacity`/`parallelTasksNo`); multi-worker uses `parallelTasksNo: 1` so reservations are inferred only from distribution, not checked by occupied slots/capacity-limited behavior. |
| 2026-06-04 | Step 1 preservation criteria | Preserve single-worker marker file content exactly equal to `RUN_ID`, multi-worker marker content exactly `RUN_ID task-N`, per-worker current-run stdio evidence, `/logs/worker/<workerId>` stdout/result evidence with `ExitSuccess`, client ACK exit checks, and no-current-run-garbage checks while adding new runtime-stat gates. |
| 2026-06-04 | Step 2 evidence | `scripts/task-schedule-smoke.sh` passed at `.tmp/task-schedule-smoke/task-schedule-smoke-20260604T123025Z-1235128`; `scripts/task-schedule-multi-worker-smoke.sh` passed at `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260604T123233Z-1237722`. Both validated `/info.runtimeQueueStats`; log stats remained LogIngest-only; multi-worker confirmed capacity-1 reservation-safe in-flight dispatch. |
| 2026-06-04 | Step 4 verification | Passed `cabal build all --enable-tests`, `scripts/task-schedule-smoke.sh` at `.tmp/task-schedule-smoke/task-schedule-smoke-20260604T124604Z-1253284`, `scripts/task-schedule-multi-worker-smoke.sh` at `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260604T124721Z-1265282`, and `make book-build`. No verification failures remain. |
| 2026-06-04 | Step 5 docs review | Must-update docs `docs/book/lotos/src/verification.md` and `docs/book/lotos/src/operations.md` were modified. README was affected and updated. `docs/book/lotos/src/task-schedule.md` was reviewed; existing scheduler/reservation behavior remains accurate, so no change was needed. No new future-work discovery required a `taskplane-tasks/CONTEXT.md` update. |
| 2026-06-04 12:18 | Review R001 | plan Step 1: APPROVE |
| 2026-06-04 12:22 | Review R002 | code Step 1: APPROVE |
| 2026-06-04 12:24 | Review R003 | plan Step 2: APPROVE |
| 2026-06-04 12:39 | Review R004 | code Step 2: APPROVE |
| 2026-06-04 12:41 | Review R005 | plan Step 3: APPROVE |
| 2026-06-04 12:44 | Review R006 | code Step 3: APPROVE |
| 2026-06-04 12:45 | Review R007 | plan Step 4: APPROVE |
| 2026-06-04 12:58 | Review R008 | code Step 4: APPROVE |

| 2026-06-04 13:01 | Worker iter 1 | done in 2698s, tools: 153 |
| 2026-06-04 13:01 | Task complete | .DONE created |