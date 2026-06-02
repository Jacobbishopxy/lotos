# TP-025: Logging Smoke, Docs, and Compatibility Cleanup — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-01
**Review Level:** 2
**Review Counter:** 10
**Iteration:** 3
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Update end-to-end smoke expectations
**Status:** ✅ Complete

- [x] Plan-review checkpoint — identify deterministic `/logs` assertions for single-worker and multi-worker smokes.
- [x] Update smoke scripts to verify current-run stdout/final-result logs through `/logs` endpoints instead of `/info.workerLoggingsMap`.
- [x] Add stats/dropped-log assertions where deterministic.

---

### Step 2: Cleanup obsolete logging coupling
**Status:** ✅ Complete

- [x] Remove or deprecate InfoStorage full-log fields/API once smoke and docs use LogIngest.
- [x] Ensure `/info` remains lightweight and still exposes scheduler state.
- [x] Refresh `docs/lb_sys.drawio` to show the final LogIngest architecture with no overlapping labels.
- [x] R005 fix: start LogIngest without the obsolete InfoStorage same-address guard and update stale tests/comments for same-address configs.

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] Code review checkpoint — review final API/docs/smoke consistency.
- [x] Run `cabal build all --enable-tests`.
- [x] Run `cabal test all` if it remains bounded/safe.
- [x] Fix smoke-discovered worker LogAck matching bug caused by wire-rounded ACK timestamps.
- [x] Run `scripts/task-schedule-smoke.sh` and `scripts/task-schedule-multi-worker-smoke.sh`.

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update README and docs with new logging behavior, endpoints, limits, and reliability caveats.
- [x] Update CONTEXT to close or refine logging redesign debt.

---

### Final Verification
**Status:** ✅ Complete

- [x] Build/tests/smoke required by PROMPT.md pass
- [x] Documentation requirements satisfied
- [x] Exactly one final TP commit exists

---

## Notes / Discoveries

- Preflight: created missing `.reviews/` directory, confirmed TP-024 is complete with `.DONE`, and reviewed git status/history; no TP-025 implementation commits exist yet beyond the orchestrator staging commit.
- Step 1 plan: update both smoke scripts to poll `/logs/worker/<workerId>` for current-run stdout messages and the final `ExitSuccess` result event; include `/logs/recent` and `/logs/stats` in evidence snapshots; assert deterministic stats (`droppedEvents`, `rejectedEvents`, and `sequenceGaps` stay `0`, expected worker count is visible, and accepted events are non-empty) without depending on legacy `/info.workerLoggingsMap`.
- Step 2 plan: make `/info` a scheduler-only snapshot by removing `workerLoggingsMap`, the legacy InfoStorage SUB/ring-buffer bridge, and the unused `TaskLogging` option; keep `/tasks`, `/garbage`, `/worker_tasks`, `/worker_stats`, and `/logs/*` routes intact; update the architecture diagram so LogIngest owns worker log ingestion/querying.
- R005 suggestion: refreshed `Lotos.Zmq.Config` comments so legacy `loggingAddr`/`loadBalancerLoggingAddr` fields are documented as compatibility/default-derivation fields while LogIngest owns retention and ROUTER/DEALER ingestion.
- R005 verification: `cabal test lotos:test:test-zmq-log-ingest lotos:test:test-zmq-log-protocol-config` passed after removing the same-address startup guard.
- Step 3 review checkpoint: first `review_step(step=3,type=code)` attempt returned UNAVAILABLE (code 143), retry returned APPROVE.
- Step 3 build verification: `cabal build all --enable-tests` completed successfully.
- Step 3 test verification: `cabal test all` completed successfully; registered suites were bounded in this workspace.
- Step 3 smoke failure/fix: multi-worker smoke initially failed because wire-rounded `Ack` timestamps prevented worker log batches from clearing in-flight state; fixed `WorkerLogTransport` ACK matching and verified with `cabal test lotos:test:test-zmq-worker-log-transport`.
- Step 3 re-verification after ACK fix: `cabal build all --enable-tests && cabal test all` completed successfully.
- Step 3 smoke verification: `scripts/task-schedule-smoke.sh` passed with evidence `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T203413Z-1363172`; `scripts/task-schedule-multi-worker-smoke.sh` passed with evidence `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260601T203500Z-1380820`.
- Step 4 docs: README, TaskSchedule MVP, build-your-own-scheduler, and logging-redesign docs now describe `/logs/*`, LogIngest endpoint/config limits, at-least-once/dedup/drop visibility, and scheduler-only `/info` snapshots.
- Step 4 CONTEXT: reliable logging hardening debt now reflects TP-025 completion and narrows remaining work to journal recovery/retention, socket HWM, and public compatibility naming cleanup.

| 2026-06-01 19:33 | Task started | Runtime V2 lane-runner execution |
| 2026-06-01 19:33 | Step 0 started | Preflight |
| 2026-06-01 19:35 | Worker iter 1 | done in 141s, tools: 21 |
| 2026-06-01 19:39 | Review R001 | plan Step 1: APPROVE |
| 2026-06-01 19:46 | Review R003 | code Step 1: APPROVE |
| 2026-06-01 19:48 | Review R004 | plan Step 2: APPROVE |
| 2026-06-01 19:56 | Review R005 | code Step 2: REVISE |

| 2026-06-01 19:58 | Worker iter 2 | done in 1386s, tools: 78 |
| 2026-06-01 19:58 | Step 2 started | Cleanup obsolete logging coupling |
| 2026-06-01 20:06 | Review R006 | code Step 2: APPROVE |
| 2026-06-01 20:08 | Review R007 | plan Step 3: APPROVE |
| 2026-06-01 20:22 | Review R009 | code Step 3: APPROVE |
| 2026-06-01 20:40 | Review R010 | code Step 3: APPROVE |

| 2026-06-01 20:49 | Worker iter 3 | done in 3027s, tools: 167 |
| 2026-06-01 20:49 | Task complete | .DONE created |