# TP-023: Log Ingest Service and Query API — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-01
**Review Level:** 2
**Review Counter:** 8
**Iteration:** 1
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Design ingestion/storage boundary
**Status:** ✅ Complete

- [x] Plan-review checkpoint — decide LogIngest module API, cache indexes, JSONL file layout, and HTTP route integration.
- [x] Keep InfoStorage scheduler snapshots lightweight; do not embed full logs in `/info` as the final direction.
- [x] Define duplicate/sequence-gap/drop accounting behavior.

---

### Step 2: Implement LogIngest service and tests
**Status:** ✅ Complete

- [x] Add a LogIngest module with bounded per-worker/per-task recent caches and append-only JSONL writer.
- [x] Add ROUTER receive + LogBatch decode + persist/cache + LogAck send flow.
- [x] Add `/logs/...` query endpoints or a dedicated log API server route, with task/worker/recent/stats lookups.
- [x] Add bounded unit tests for cache eviction, duplicate handling, sequence-gap detection, and JSON encoding/API shape.
- [x] R005 fix: enforce `logIngestReadCacheMaxTasks` across task-indexed caches and cover distinct-task eviction.
- [x] R005 fix: reject mismatched ROUTER envelope worker IDs before persistence/cache mutation and cover the identity mismatch.
- [x] R005 fix: count invalid-event rejection reasons exactly once and cover validation-limit stats.

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] Code review checkpoint — review concurrency/resource handling and API shape.
- [x] Run targeted LogIngest tests.
- [x] Run `cabal build all --enable-tests` and relevant bounded regression tests.

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update docs with endpoint names, persistence layout, and limitations.
- [x] Record any worker-side follow-up in STATUS.md/CONTEXT.

---

### Final Verification
**Status:** ✅ Complete

- [x] Build/tests/smoke required by PROMPT.md pass
- [x] Documentation requirements satisfied
- [x] Exactly one final TP commit exists

---

## Notes / Discoveries

- Preflight verified required task/source/doc paths, created missing `.reviews/` directory, confirmed TP-022 is complete (`.DONE` + complete STATUS) and LogBatch/LogAck/LogIngestConfig surfaces exist, and recorded `13b1a25` as the pre-TP baseline for later single-commit squashing.
- Step 1 design draft for plan review: add `Lotos.Zmq.LBS.LogIngest` with a `LogIngestState` MVar-owned store plus narrow APIs `newLogIngestState`, `ingestLogBatch`, `runLogIngest`, recent-query helpers, and stats snapshots. The store keeps bounded caches by worker, by task, and by `(worker, task)` using `logIngestReadCacheSize`, caps bucket count with `logIngestReadCacheMaxTasks`, and appends accepted non-duplicate `LogEvent`s to JSONL at `logIngestJournalPath` before advancing state/ACK.
- Step 1 design draft for HTTP/integration: `runLBS` will create a LogIngest state, start the ROUTER service only when `logIngestAddr` does not collide with legacy `InfoStorageConfig.loggingAddr`, and pass the state to `InfoStorage` so `/NAME/logs/recent`, `/NAME/logs/worker/:workerId`, `/NAME/logs/task/:taskId`, and `/NAME/logs/stats` read from LogIngest without embedding structured logs into `/NAME/info`. The legacy PUB/SUB `workerLoggingsMap` remains only for compatibility until the worker transport switch.
- Step 1 design draft for accounting: ordinary events cover their `seq`; duplicate covered sequence numbers are skipped and counted, accepted events are persisted/cached once, hidden sequence gaps are counted and reported in stats/rejected reasons while ACK `acceptedThrough` stays at the highest contiguous covered sequence, and explicit gap/drop events with `droppedFrom`/`droppedThrough` count the dropped span as visible coverage so ACKs can advance through declared drops.
- Step 1 plan review returned APPROVE; code review returned APPROVE for the design/status diff.
- Step 2 plan review returned APPROVE; implementation baseline is `308e2fa1860d7d5dbc96ec1738c5cad8ae8c9679`.
- Step 2 targeted test `cabal test lotos:test:test-zmq-log-ingest` passed (7 HUnit cases) after adding LogIngest cache/journal/router/API coverage.
- Step 2 first code review was unavailable, second code review R005 returned REVISE. Suggestion logged: apply `logIngestSocketHWM` to the ROUTER socket when the ZMQ wrapper supports it.
- R005 distinct-task eviction fixed by capping `storeByTask`, evicting corresponding `(worker, task)` buckets, and adding a targeted HUnit case.
- R005 ROUTER identity fixed by checking envelope routing id before ingestion and ACKing a rejected mismatch without mutating journal/cache state.
- R005 rejection accounting fixed by collecting validation errors during the fold and incrementing `counterRejectedEvents` once; `cabal test lotos:test:test-zmq-log-ingest` now passes 10 HUnit cases.
- Step 2 code re-review returned APPROVE after R005 fixes.
- Step 3 plan review returned APPROVE; the Step 2 R006 code review approved the LogIngest concurrency/resource/API shape before verification.
- Step 3 targeted LogIngest verification passed: `cabal test lotos:test:test-zmq-log-ingest` (10 HUnit cases).
- Step 3 full/related verification passed: `cabal build all --enable-tests`, `cabal test lotos:test:test-zmq-log-protocol-config` (6 cases), `cabal test lotos:test:test-zmq-worker-frames` (13 cases), and `cabal test lotos:test:test-conc-executor` (5 cases).
- Step 3 code review returned APPROVE for verification evidence/status.
- Documentation updated in `docs/logging-redesign.md` with `/logs/...` endpoints, JSONL persistence/cache layout, staged runtime guard, and remaining limitations.
- `taskplane-tasks/CONTEXT.md` follow-up updated to focus remaining work on worker DEALER retry/drop handling, split runtime config enablement, restart recovery/retention, and PUB/SUB compatibility removal.

| 2026-06-01 17:27 | Task started | Runtime V2 lane-runner execution |
| 2026-06-01 17:27 | Step 0 started | Preflight |
| 2026-06-01 17:37 | Review R001 | plan Step 1: APPROVE |
| 2026-06-01 17:40 | Review R002 | code Step 1: APPROVE |
| 2026-06-01 17:44 | Review R003 | plan Step 2: APPROVE |
| 2026-06-01 18:09 | Review R005 | code Step 2: REVISE |
| 2026-06-01 18:21 | Review R006 | code Step 2: APPROVE |
| 2026-06-01 18:22 | Review R007 | plan Step 3: APPROVE |
| 2026-06-01 18:27 | Review R008 | code Step 3: APPROVE |

| 2026-06-01 18:31 | Worker iter 1 | done in 3828s, tools: 149 |
| 2026-06-01 18:31 | Task complete | .DONE created |