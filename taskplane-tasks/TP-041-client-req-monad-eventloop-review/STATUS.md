# TP-041: Review client REQ path under monad/EventLoop architecture — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-06-03
**Review Level:** 2
**Review Counter:** 6
**Iteration:** 2
**Size:** M

> **Hydration:** Checkboxes represent meaningful outcomes, not individual code
> changes. Workers expand steps when runtime discoveries warrant it.

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] Dependencies satisfied
- [x] Current git/task status reviewed so this TP finishes as exactly one final commit

---

### Step 1: Evaluate client REQ architecture
**Status:** ✅ Complete

- [x] Plan-review checkpoint — compare direct monadic REQ with EventLoop transceiver for request/ACK traffic.
- [x] Decide timeout/cancellation behavior and whether it belongs in public client API.
- [x] Preserve client routing-id and ACK frame semantics.

---

### Step 2: Implement selected client path
**Status:** ✅ Complete

- [x] If keeping direct: ensure the client path consistently uses monad context and add bounded receive behavior if appropriate.
- [x] N/A (direct path selected): EventLoop migration intentionally not applied to REQ request/ACK.
- [x] Update TaskSchedule client executable and public facade as needed.

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] Code review checkpoint — review public client API compatibility and frame ordering.
- [x] Run client ACK frame tests.
- [x] Run `cabal build all --enable-tests`.
- [x] Run single-worker smoke to prove live client submission still succeeds.

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] Update README client usage if public behavior changes.
- [x] Update `taskplane-tasks/CONTEXT.md` with final client path decision.
- [x] Ensure exactly one final TP commit exists.

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|

---

## Notes / Discoveries

- Step 1 plan: keep the client REQ path direct and monadic rather than moving it to `EventLoop`; the client submits one synchronous request and waits for one ACK, so an EventLoop transceiver would add a worker thread/mailbox/drop boundary without improving routing semantics. Use the existing public `ClientServiceConfig.reqTimeoutSec` as the bounded ACK timeout, implement it in `sendTaskRequest` with an explicit receive timeout that returns `Nothing` instead of crashing, and preserve the existing REQ `Z_RoutingId` plus broker ACK frame order (`ClientAck clientId reqId ack` -> client receives `toZmq ack`).
- Step 2 migration branch is intentionally N/A because Step 1 selected the direct monadic REQ path; no EventLoop socket registration or mailbox command surface was added.
- Verification: `cabal test lotos:test:test-zmq-client-ack-frames` passed 3 cases, covering raw client ACK frames, `sendTaskRequest` timeout -> `Nothing`, and malformed request decode failure.
- Verification: `cabal build all --enable-tests` completed successfully, compiling lotos tests/executables and TaskSchedule libraries/tests/executables.
- Verification: `scripts/task-schedule-smoke.sh` passed; evidence at `.tmp/task-schedule-smoke/task-schedule-smoke-20260603T150125Z-3761704`, with ts-client exit code 0, fresh marker proof, and worker logging evidence.

| 2026-06-03 14:43 | Task started | Runtime V2 lane-runner execution |
| 2026-06-03 14:43 | Step 0 started | Preflight |
| 2026-06-03 14:45 | Worker iter 1 | done in 128s, tools: 28 |
| 2026-06-03 14:48 | Review R001 | code Step 1: APPROVE |
| 2026-06-03 14:49 | Review R002 | plan Step 2: APPROVE |
| 2026-06-03 14:56 | Review R003 | code Step 2: APPROVE |
| 2026-06-03 14:58 | Review R004 | plan Step 3: APPROVE |
| 2026-06-03 14:59 | Review R005 | code Step 3: APPROVE |
| 2026-06-03 15:03 | Review R006 | code Step 3: APPROVE |

| 2026-06-03 15:06 | Worker iter 2 | done in 1286s, tools: 99 |
| 2026-06-03 15:06 | Task complete | .DONE created |