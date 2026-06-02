# TP-026: LogIngest Durability and Retention Hardening — Status

**Current Step:** Final Verification
**Status:** ✅ Complete
**Last Updated:** 2026-06-02
**Review Level:** 2
**Review Counter:** 5
**Iteration:** 1
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] TP-025 reliable logging state and smoke evidence understood
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Define durability/retention contract
**Status:** ✅ Complete

- [x] Restart recovery contract defined
- [x] Retention/compaction contract defined
- [x] Socket HWM support/limitations identified
- [x] Targeted test plan defined

---

### Step 2: Implement restart recovery and retention enforcement
**Status:** ✅ Complete

- [x] Journal reload/rebuild path implemented
- [x] Malformed/partial journal handling implemented
- [x] Retention/compaction/rotation implemented
- [x] Socket HWM applied or limitation documented
- [x] Existing `/logs/*` API and at-least-once semantics preserved

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] Restart recovery tests added/passing
- [x] Retention/malformed journal tests added/passing
- [x] HWM/config tests added/passing if changed
- [x] Targeted logging test command passes
- [x] `cabal build all --enable-tests` passes

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] `docs/logging-redesign.md` updated
- [x] `taskplane-tasks/CONTEXT.md` updated with `Next Task ID: TP-027` and logging hardening status
- [x] Discoveries logged in STATUS.md

---

### Final Verification
**Status:** ✅ Complete

- [x] Completion criteria satisfied
- [x] Exactly one final TP commit exists

---

## Notes / Discoveries

- Preflight: created missing `.reviews/` directory, confirmed TP-025 is complete, and reviewed logging docs/CONTEXT. Current reliable logging state: LogIngest DEALER/ROUTER path is live, `/info` no longer carries worker logs, `/logs/*` provides worker/recent/task/stats queries, worker batches retry until `LogAck`, and TP-025 smoke evidence passed at `.tmp/task-schedule-smoke/task-schedule-smoke-20260601T203413Z-1363172/` plus `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260601T203500Z-1380820/`. Remaining hardening is restart journal recovery, retention/compaction, and socket HWM.
- Preflight git status: current branch `task/xiey-lane-1-20260602T094339`, HEAD `8a36fa5` is orchestrator staging on top of TP-025 (`9d685e3`); final TP-026 history must be squashed to one Lore-protocol commit.
- Step 1 restart contract: `newLogIngestState` should reload the configured JSONL journal on broker startup. Valid accepted `LogEvent` lines rebuild the bounded recent/worker/task caches and each worker's sequence coverage/`acceptedThrough` watermark using the same idempotency rules as live ingest, without rewriting duplicate entries. Recovered stats should reflect durable journal contents where meaningful (`acceptedEvents`, sequence gaps, visible drops, workers/tasks, accepted-through); transient duplicate/rejected counts only persist if captured by a compaction checkpoint, and otherwise restart at zero. A retry after broker restart for already-covered sequences must ACK as duplicate rather than append again.
- Step 1 retention contract: `logIngestRetentionBytes` is an approximate on-disk cap for the journal, not a memory-cache size. After successful appends, LogIngest should compact when the journal exceeds the positive cap by rewriting a bounded suffix plus a checkpoint that preserves worker sequence coverage/counters needed for restart idempotency. Malformed/partial lines may be discarded during compaction. If the cap is too small to hold the checkpoint plus required covered-ahead events, correctness wins over the byte cap and docs should call the cap approximate. Operators see retention through bounded `/logs/*` results and checkpoint/malformed counters rather than hidden unbounded growth.
- Step 1 HWM contract: the current `zmqx` surface supports `Zmqx.setSocketOpt` with `Z_SndHWM` and `Z_RcvHWM` (confirmed in GHCi after dependency fetch). Apply `max 1 logIngestSocketHWM` as both send and receive HWM on the broker LogIngest ROUTER before `bind` and the worker logging DEALER before `connect`, alongside the existing routing id option. No multipart frame shape changes are needed.
- Step 1 targeted test plan: extend `test-zmq-log-ingest` with restart reload from an existing journal (caches, stats, accepted-through, duplicate retry after restart), malformed/partial JSONL line tolerance with a visible stat, and retention/compaction proving the journal is bounded while restart idempotency survives. Extend protocol/config or worker transport tests only if HWM parsing/defaults or worker socket behavior changes beyond applying existing config; otherwise run the existing config/worker suites for compatibility.
- Step 1 plan review: `review_step(step=1,type=plan)` returned APPROVE.
- Step 2 plan review: `review_step(step=2,type=plan)` returned APPROVE before implementation.
- Step 2 implementation: `newLogIngestState` now loads existing journal entries into caches, stats, worker sequence coverage, and accepted-through state before the ROUTER starts; `cabal build lotos` compiled the library after the reload changes.
- Step 2 malformed handling: journal replay skips malformed/partial JSONL lines and invalid recovered drop ranges, increments a visible `malformedJournalLines` stats field, and continues startup instead of throwing.
- Step 2 retention implementation: after accepted-event appends, LogIngest rewrites an oversized journal to a checkpoint plus the newest valid event suffix that fits the approximate `logIngestRetentionBytes` cap; the checkpoint preserves counters and worker sequence coverage so restart duplicate suppression survives compaction.
- Step 2 HWM implementation: LogIngest ROUTER and worker logging DEALER both set `Z_SndHWM` and `Z_RcvHWM` from `max 1 logIngestSocketHWM` before bind/connect; no unsupported Zmqx limitation remains for this knob.
- Step 2 API/semantics verification: existing `test-zmq-log-ingest` passed after the implementation, preserving query JSON, stats keys, duplicate handling, identity mismatch rejection, and ROUTER/DEALER ACK behavior while adding the new `malformedJournalLines` stats key.
- Step 2 code review: temporary implementation commit `c5ca731` reviewed with `review_step(step=2,type=code,baseline=8a36fa5)` and returned APPROVE.
- Step 3 restart tests: added `restartRecoveryRebuildsCachesStatsAndWatermark`; `cabal test lotos:test:test-zmq-log-ingest` passed with 13 cases.
- Step 3 retention/malformed tests: added `malformedJournalLinesAreSkippedDuringRecovery` and `retentionCompactsJournalAndRecoveryKeepsWatermark`; same `test-zmq-log-ingest` run passed and verifies malformed counters, bounded compaction, retained suffix query usefulness, and duplicate suppression after restart.
- Step 3 HWM/config tests: extended `test-zmq-log-protocol-config` HWM default/explicit parsing assertions; `cabal test lotos:test:test-zmq-log-protocol-config` passed with 6 cases.
- Step 3 targeted logging command: `cabal test lotos:test:test-zmq-log-ingest lotos:test:test-zmq-log-protocol-config lotos:test:test-zmq-worker-log-transport` passed (13 + 6 + 5 cases).
- Step 3 full build gate: `cabal build all --enable-tests` completed successfully.
- Step 3 code review: temporary testing commit `0c22129` reviewed with `review_step(step=3,type=code,baseline=f06c1f2)` and returned APPROVE.
- Step 4 docs: `docs/logging-redesign.md` now describes TP-026 restart replay, checkpoint retention, malformed journal accounting, applied socket HWM, and remaining compatibility-name caveat.
- Step 4 context: `taskplane-tasks/CONTEXT.md` now sets `Next Task ID: TP-027`, marks reliable logging hardening resolved through TP-026, and carries legacy logging compatibility-name cleanup as its own follow-up.
- Step 4 discoveries: Zmqx exposes both `Z_SndHWM` and `Z_RcvHWM`; lazy journal reads can keep test files locked during restart-and-append cycles, so LogIngest recovery now uses strict file reads; no `docs/task-schedule-mvp.md` update was needed because user-facing smoke semantics stayed at `/logs/*` at-least-once delivery.
- Final verification: completion criteria satisfied by restart recovery/retention/HWM implementation, `test-zmq-log-ingest` restart/malformed/retention coverage, HWM config assertions, targeted logging test pass, `cabal build all --enable-tests` pass, and documentation/context updates.
- Final git verification: squashed temporary Taskplane commits into one TP-026 commit on top of orchestrator staging; `git rev-list --count 8a36fa5..HEAD` returned `1`, and the final STATUS/message amend preserves that single-commit history.

| 2026-06-02 01:43 | Task started | Runtime V2 lane-runner execution |
| 2026-06-02 01:43 | Step 0 started | Preflight |
| 2026-06-02 01:52 | Review R001 | plan Step 1: APPROVE |
| 2026-06-02 01:54 | Review R002 | plan Step 2: APPROVE |
| 2026-06-02 02:08 | Review R003 | code Step 2: APPROVE |
| 2026-06-02 02:10 | Review R004 | plan Step 3: APPROVE |
| 2026-06-02 02:20 | Review R005 | code Step 3: APPROVE |

| 2026-06-02 02:27 | Worker iter 1 | done in 2599s, tools: 144 |
| 2026-06-02 02:27 | Task complete | .DONE created |