# TP-022: Reliable Log Protocol and Config — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-02
**Review Level:** 2
**Review Counter:** 7
**Iteration:** 3
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Design protocol compatibility boundary
**Status:** ✅ Complete

- [x] Plan-review checkpoint — decide names/exports for `LogEvent`, `LogBatch`, `LogAck`, stream/level/drop-policy types, and whether they are public via `Lotos.Zmq`.
- [x] Preserve existing `WorkerLogging` frame ordering and compatibility until the transport switch TP removes or adapts it.
- [x] Define config defaults and backward-compatible JSON parsing for existing broker/worker configs.

---

### Step 2: Implement protocol/config and tests
**Status:** ✅ Complete

- [x] Add structured log protocol types and ToZmq/FromZmq/Aeson coverage.
- [x] Add logging config knobs for ROUTER/DEALER address, HWM, batch size, line size, cache limits, persistence path, retention, and drop policy.
- [x] Update exports/documentation comments without adding dependencies.
- [x] R004 fix: reject negative/overflow `Word64` sequence frames and add regression plus literal frame-order assertions for `LogBatch`/`LogAck`.

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] Code review checkpoint — review protocol frame ordering and config compatibility.
- [x] Run targeted protocol/config tests.
- [x] Run `cabal build all --enable-tests` and a targeted terminating test suite relevant to changed code.

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update `docs/logging-redesign.md` with exact type/config names if they differ from the initial design.
- [x] Update CONTEXT with remaining logging transport work.

---

### Final Verification
**Status:** ✅ Complete

- [x] Build/tests/smoke required by PROMPT.md pass
- [x] Documentation requirements satisfied
- [x] Exactly one final TP commit exists

---

## Notes / Discoveries

- Step 1 plan: add new public protocol/config names through `Lotos.Zmq`: `LogStream`, `LogLevel`, `LogDropPolicy`, `LogEvent`, `LogBatch`, `LogAck`, and `LogIngestConfig`; keep `WorkerLogging` unchanged for the current PUB/SUB path. Use fixed multipart frames for new log messages and optional/defaulted JSON parsing so old broker/worker configs still decode without new fields.
- Compatibility boundary: leave existing `WorkerLogging` serialization as exactly `[taskUuid, loggingText]`; the PUB topic/routing worker id remains outside that payload until a later transport-switch TP rewires runtime logging.
- Config compatibility plan: add optional `logIngest` to `BrokerServiceConfig` and optional `workerLogging` to `WorkerServiceConfig`; when omitted, defaults derive the new reliable-log endpoint from current `infoStorage.loggingAddr` / `loadBalancerLoggingAddr` so existing JSON files continue to parse.
- Evidence: `cabal test lotos:test:test-zmq-log-protocol-config` passed after adding `LogEvent`/`LogBatch`/`LogAck` frame and JSON coverage, including a legacy `WorkerLogging` frame-order assertion.
- R004 suggestion logged: consider deriving partial nested `logIngest` defaults from the parent broker/worker logging address instead of standalone `5558` in a future compatibility polish pass.
- Evidence: R004 revision verified with `cabal test lotos:test:test-zmq-log-protocol-config` (6 cases, PASS).
- Evidence: Step 3 targeted protocol/config gate reran `cabal test lotos:test:test-zmq-log-protocol-config` (6 cases, PASS).
- Evidence: `cabal build all --enable-tests` passed, followed by `cabal test lotos:test:test-zmq-worker-frames` (13 cases, PASS).
- Evidence: `taskplane-tasks/CONTEXT.md` now tracks remaining LogIngest transport work after TP-022: broker service, worker DEALER/retry/drop handling, journal persistence/compaction, read cache, and InfoStorage rewire.
- Evidence: final gate reran `cabal build all --enable-tests` and `cabal test lotos:test:test-zmq-log-protocol-config` (6 cases, PASS).
- Evidence: documentation gate verified `docs/logging-redesign.md` exact TP-022 type/config names and `taskplane-tasks/CONTEXT.md` remaining transport work are both updated.
- Evidence: final history was squashed to one TP-022 commit on top of `463c939`.

| 2026-06-01 16:43 | Task started | Runtime V2 lane-runner execution |
| 2026-06-01 16:43 | Step 0 started | Preflight |
| 2026-06-01 16:48 | Review R001 | plan Step 1: APPROVE |
| 2026-06-01 16:51 | Review R002 | code Step 1: APPROVE |
| 2026-06-01 16:53 | Review R003 | plan Step 2: APPROVE |
| 2026-06-01 17:06 | Review R004 | code Step 2: REVISE |
| 2026-06-01 17:11 | Review R005 | code Step 2: APPROVE |
| 2026-06-01 17:13 | Review R006 | plan Step 3: APPROVE |
| 2026-06-01 17:16 | Review R007 | code Step 3: APPROVE |

| 2026-06-01 17:18 | Worker iter 1 | done in 2147s, tools: 102 |
| 2026-06-01 17:18 | Step 4 started | Documentation & Delivery |
| 2026-06-01 17:20 | Worker iter 2 | done in 125s, tools: 16 |
| 2026-06-01 17:25 | Worker iter 3 | done in 287s, tools: 25 |
| 2026-06-01 17:25 | Task complete | .DONE created |