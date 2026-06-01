# TP-017: Multi-Worker Scheduling Smoke — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-01
**Review Level:** 2
**Review Counter:** 6
**Iteration:** 1
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] TP-016 complete and single-worker smoke is green

---

### Step 1: Design multi-worker smoke
**Status:** ✅ Complete

- [x] Extend-vs-new smoke helper decision made
- [x] Worker configs/IDs and expected evidence defined
- [x] Task count, timeout, cleanup, pass/fail criteria defined
- [x] Unique per-run client configs/IDs for concurrent submissions defined
- [x] Deterministic per-worker execution proof strategy defined

---

### Step 2: Implement multi-worker smoke path
**Status:** ✅ Complete

- [x] Server plus at least two workers started
- [x] Multiple fresh task JSON files submitted
- [x] Workers verified in `/worker_stats`
- [x] Task markers/logs verified for current run
- [x] Cleanup works

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] `cabal build all --enable-tests` passes
- [x] `cabal test all` passes
- [x] Existing single-worker smoke passes
- [x] New multi-worker smoke passes or exact blocker documented

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] README updated
- [x] MVP docs updated
- [x] Context debt updated if needed
- [x] Discoveries logged

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | Plan | Step 1 | REVISE | .reviews/R001-plan-step1.md |
| R002 | Plan | Step 1 | APPROVE | inline |
| R003 | Plan | Step 2 | UNAVAILABLE | inline |
| R004 | Code | Step 2 | APPROVE | inline |
| R005 | Plan | Step 3 | APPROVE | inline |
| R006 | Code | Step 3 | APPROVE | inline |

---

## Discoveries

- Multi-worker smoke is green with generated `smokeWorker_1`/`smokeWorker_2` configs and four current-run tasks; evidence: `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260601T110611Z-1239027/result.env`.
- Unique client IDs are required for concurrent smoke submissions because the client REQ routing id comes from `clientId`; the new helper generates `smokeClient_N` configs per task.
- No new scheduling debt was observed: each worker processed current-run work, all markers/logging passed, garbage stayed clean, and a post-smoke process audit found no leftover TaskSchedule processes.

---

## Execution Log

| 2026-06-01 10:35 | Task started | Runtime V2 lane-runner execution |
| 2026-06-01 10:35 | Step 0 started | Preflight |
| 2026-06-01 10:37 | Step 0 complete | TP-016 present in history; single-worker smoke PASS at .tmp/task-schedule-smoke/task-schedule-smoke-20260601T103655Z-1017381/ |
| 2026-06-01 10:37 | Step 1 started | Design multi-worker smoke |
| 2026-06-01 10:45 | Step 1 plan review approved | R001 issues addressed with unique client configs and deterministic per-worker proof controls |
| 2026-06-01 10:45 | Step 2 started | Implement multi-worker smoke path |
| 2026-06-01 10:46 | Step 2 plan review unavailable | Proceeding with approved Step 1 design controls |
| 2026-06-01 11:00 | Step 2 code review approved | New multi-worker helper reviewed after implementation commit 236e07d |
| 2026-06-01 11:00 | Step 3 started | Testing & Verification |
| 2026-06-01 11:01 | Step 3 plan review approved | Verification sequence approved |
| 2026-06-01 11:03 | Build gate passed | `cabal build all --enable-tests` |
| 2026-06-01 11:04 | Regression gate passed | `cabal test all` |
| 2026-06-01 11:05 | Single-worker smoke passed | `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T110454Z-1237282/result.env` status=PASS |
| 2026-06-01 11:07 | Multi-worker smoke passed | `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260601T110611Z-1239027/result.env` status=PASS, workers=2, tasks=4 |
| 2026-06-01 11:08 | Cleanup audit passed | `pgrep -af 'ts-(server|worker|client)|TaskSchedule:exe:ts-(server|worker|client)'` returned no processes |
| 2026-06-01 11:09 | Step 3 code review approved | Smoke helper and verification evidence approved |
| 2026-06-01 11:09 | Step 4 started | Documentation & Delivery |
| 2026-06-01 11:13 | Step 4 complete | README, MVP docs, context, and STATUS discoveries updated |
| 2026-06-01 11:13 | Task complete | All TP-017 steps complete; final history squashed to one commit before handoff |
| 2026-06-01 11:16 | Worker iter 1 | done in 2435s, tools: 120 |
| 2026-06-01 11:16 | Task complete | .DONE created |
---

## Blockers

---

## Notes

- Step 1 design decision: add a separate `scripts/task-schedule-multi-worker-smoke.sh` rather than mode-switching the existing single-worker helper. This keeps the green TP-016/TP-013 single-worker path stable and lets the new helper use worker/task arrays without making the single-worker script harder to reason about.
- Step 1 worker/evidence design: generate per-run worker config files under the evidence directory for `smokeWorker_1` and `smokeWorker_2` (same backend/logging endpoints as sample config, distinct worker IDs and inproc pair addresses). Pass evidence should include both IDs in `/SimpleServer/worker_stats`, current-run task content in each worker's stdio log, current-run worker logging/`ExitSuccess` in `/SimpleServer/info`, and per-task marker files written during the run.
- Step 1 pass/fail design: default to 2 workers and 4 fresh task JSON files, launch client submissions concurrently after both workers are ready, and use a generated broker config with a high task-processor notify threshold plus a bounded batching window so ACKed tasks are queued before the first scheduling pass. Task commands print current-run labels, write per-task markers, and briefly stay alive so per-worker processing evidence can be captured. The helper fails on missing ACKs, missing worker stats, stale/missing markers, missing current-run evidence in each worker's dedicated stdio log, missing current-run worker logging/`ExitSuccess` in `/info`, current-run garbage, or process early exit, and traps cleanup to terminate every spawned server/worker/client process group.
- R001 suggestion: Step 2 implementation notes should preserve exact evidence file paths for per-worker stats, logs, markers, ACKs, garbage absence, and cleanup.
- R001 client identity revision: the multi-worker helper will generate one client config per submitted task under the evidence directory (`smokeClient_1`, `smokeClient_2`, ...), then run concurrent `ts-client` processes with distinct REQ routing IDs so ROUTER identity collisions cannot cause ACK timeouts.
- R001 per-worker proof revision: deterministic proof will come from (1) all workers registered before submission, (2) all clients ACKing within the batching window, (3) at least one current-run task label appearing in every worker-specific stdio log, (4) all task marker files matching the run, and (5) final endpoint snapshots showing both worker IDs plus current-run logging/`ExitSuccess`; if all work remains attributed to one worker after these race controls, the smoke reports a scheduling/runtime blocker rather than silently passing.
- Step 3 evidence: build and regression gates passed; single-worker evidence is `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T110454Z-1237282/`; multi-worker evidence is `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260601T110611Z-1239027/`; no `ts-server`, `ts-worker`, or `ts-client` processes remained after cleanup audit.
| 2026-06-01 10:43 | Review R001 | plan Step 1: REVISE |
| 2026-06-01 10:48 | Review R002 | plan Step 1: APPROVE |
| 2026-06-01 11:01 | Review R004 | code Step 2: APPROVE |
| 2026-06-01 11:03 | Review R005 | plan Step 3: APPROVE |
| 2026-06-01 11:12 | Review R006 | code Step 3: APPROVE |
