# TP-037: Migrate LogIngest ROUTER to EventLoop — Status

**Current Step:** Step 5: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-03
**Review Level:** 3
**Review Counter:** 9
**Iteration:** 1
**Size:** L

> **Hydration:** Checkboxes represent meaningful outcomes, not individual code
> changes. Workers expand steps when runtime discoveries warrant it.

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Design LogIngest EventLoop ownership
**Status:** ✅ Complete

- [x] Plan-review checkpoint — decide ROUTER transceiver endpoint, mailbox capacity, ACK send path, and how ingestion work is kept off EventLoop callbacks.
- [x] R001 revision: replace built-in EventLoop `Mailbox` delivery with a concrete overload-accounting dispatch mechanism implementable by the current API.
- [x] Preserve worker routing-id frame handling and `LogBatch`/`LogAck` frame ordering.
- [x] Decide how malformed frames and journal errors are accounted under mailbox dispatch.

---

### Step 2: Implement EventLoop-backed ingestion
**Status:** ✅ Complete

- [x] Register LogIngest ROUTER as an EventLoop transceiver with explicit context.
- [x] Drain mailbox frames in the ingestion loop, apply existing dedupe/journal/retention logic, and send ACKs via EventLoop.
- [x] Preserve existing HTTP query/storage behavior.

---

### Step 3: Validate durability and backpressure semantics
**Status:** ✅ Complete

- [x] Ensure at-least-once semantics are still documented; do not claim exactly-once.
- [x] Verify mailbox-full handling cannot silently hide accepted batches without observable accounting.
- [x] Keep worker retry/delayed ACK behavior compatible.

---

### Step 4: Testing & Verification
**Status:** ✅ Complete

- [x] Test-review checkpoint — review durability, malformed-frame, ACK, and retention coverage.
- [x] Run `cabal test lotos:test:test-zmq-log-ingest lotos:test:test-zmq-worker-log-transport lotos:test:test-zmq-log-protocol-config`.
- [x] Run `cabal build all --enable-tests`.
- [x] Run single and multi-worker smoke scripts.

---

### Step 5: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update `docs/logging-redesign.md` with LogIngest EventLoop ownership if user-facing enough.
- [x] Update `taskplane-tasks/CONTEXT.md` with migration status and risks.
- [x] Ensure exactly one final TP commit exists.

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|

---

## Notes / Discoveries

- Preflight evidence: all scoped files exist; `git log --grep` shows TP-034 and TP-036 merge commits present; initial git status only had task STATUS.md modified by runtime/preflight bookkeeping.
- Step 1 design draft (R001 superseded mailbox portion): keep `LogIngest` ROUTER socket opened/bound under `Logger.LotosApp`'s explicit ZMQ context, then register it as a single EventLoop transceiver endpoint (planned name `logIngestRouter`) using `Zmqx.EventLoop.withEventLoopIn`. Use `Callback` delivery, not built-in `Mailbox`, so the callback can perform only nonblocking `isFullTBQueue`/`writeTBQueue` dispatch into a LogIngest-owned bounded STM queue and increment an overload counter when the queue is full. The ingestion loop remains the owner of decoding, journal append, retention, and ACK construction by draining that queue outside the EventLoop worker thread. ACKs are sent back through `Zmqx.EventLoop.sends` on the same transceiver endpoint as `routingFrame : toZmq ack`. Size the queue from `logIngestSocketHWM` with a positive floor rather than `logIngestBatchMaxRecords`; record queue-full events in stats/logs and do not ACK messages that were not enqueued. Preserve ROUTER envelope first-frame handling exactly: decode the routing-id frame separately, decode `LogBatch` from the remaining frames, require routing id equals `logBatchWorkerId`, and serialize ACK frames as routing frame followed by existing `LogAck` protocol frames. Malformed frames remain logged and counted as rejected/malformed where possible; journal append failures still prevent ACK so worker retry preserves at-least-once semantics.
- R001 suggestion accepted: queue capacity should derive from `logIngestSocketHWM`/dedicated log-ingest config, not the per-batch `logIngestBatchMaxRecords` limit.
- Step 1 malformed/error accounting decision: add explicit store-counter helpers for broker-side dispatch/decode rejections so empty ROUTER frames, routing-id decode failures, `LogBatch` decode failures, routing mismatch ACKs, and callback queue-full drops have visible `rejectedEvents` accounting/log lines. Keep journal append failures on the existing no-ACK path: the exception prevents the ACK, leaves accepted state unadvanced, and worker retry preserves at-least-once delivery.
- Step 2 targeted verification: `cabal test lotos:test:test-zmq-log-ingest` passed (13 cases), covering cache/query/stats, journal recovery/retention, ROUTER ACKs, same-address startup, and routing mismatch behavior under the EventLoop-backed implementation.
- Step 3 backpressure evidence: the implementation deliberately avoids `Zmqx.EventLoop.Mailbox` for broker dispatch; the EventLoop `Callback` uses `isFullTBQueue`/`writeTBQueue` against a LogIngest-owned bounded queue and increments `logIngestStateDispatchRejected`, which is included in `/logs/stats.rejectedEvents`, when the queue is full. The routing-mismatch regression now asserts rejected accounting, and `cabal test lotos:test:test-zmq-log-ingest` passed after that assertion was added.
- Step 3 worker compatibility evidence: `cabal test lotos:test:test-zmq-worker-log-transport` passed (7 cases), including delayed EventLoop ACK clearing before retry.
- Step 4 targeted suite evidence: `cabal test lotos:test:test-zmq-log-ingest lotos:test:test-zmq-worker-log-transport lotos:test:test-zmq-log-protocol-config` passed (13 + 7 + 6 cases).
- Step 4 build evidence: `cabal build all --enable-tests` completed successfully.
- Step 4 smoke evidence: `scripts/task-schedule-smoke.sh` passed with evidence at `.tmp/task-schedule-smoke/task-schedule-smoke-20260603T125829Z-3444310`; `scripts/task-schedule-multi-worker-smoke.sh` passed with evidence at `.tmp/task-schedule-multi-worker-smoke/task-schedule-multi-worker-smoke-20260603T125921Z-3446340`.

| 2026-06-03 12:32 | Task started | Runtime V2 lane-runner execution |
| 2026-06-03 12:32 | Step 0 started | Preflight |
| 2026-06-03 12:35 | Review R001 | plan Step 1: REVISE |
| 2026-06-03 12:37 | Review R002 | plan Step 1: APPROVE |
| 2026-06-03 12:39 | Review R003 | code Step 1: APPROVE |
| 2026-06-03 12:40 | Review R004 | plan Step 2: APPROVE |
| 2026-06-03 12:48 | Review R005 | code Step 2: APPROVE |
| 2026-06-03 12:49 | Review R006 | plan Step 3: APPROVE |
| 2026-06-03 12:54 | Review R007 | code Step 3: APPROVE |
| 2026-06-03 12:56 | Review R008 | plan Step 4: APPROVE |
| 2026-06-03 13:03 | Review R009 | code Step 4: APPROVE |

| 2026-06-03 13:05 | Worker iter 1 | done in 2032s, tools: 123 |
| 2026-06-03 13:05 | Task complete | .DONE created |