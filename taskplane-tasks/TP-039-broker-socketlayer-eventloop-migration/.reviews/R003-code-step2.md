## Code Review: Step 2: Implement EventLoop-owned SocketLayer

### Verdict: REVISE

### Summary
The sockets are registered under `withEventLoopIn` and the send paths have moved to `EventLoop.sends`, but the new mailbox drain loop is not correct enough for broker traffic. Declared quality-check commands were not configured in `.pi/taskplane-config.json` and no `package.json` exists; I also ran `cabal build lotos`, which reported `Up to date`.

### Issues Found
1. **[lotos/src/Lotos/Zmq/LBS/SocketLayer.hs:160] [important]** — Batch draining recursively calls `handleSocketLayerFrames`, and each handled queued frame starts another full `socketLayerDrainBatchLimit` drain. This defeats the intended bounded batch behavior and resets the drain preference to frontend on every nested call; under a large/continuous frontend backlog, backend worker status and TaskProcessor frames can be starved, risking missed liveness/retry/garbage/notify processing. Fix: split “handle one frame” from “drain a batch”; have the batch loop call only the one-frame dispatcher, decrement once per frame, and return to `layerLoop` after the fixed limit.
2. **[lotos/src/Lotos/Zmq/LBS/SocketLayer.hs:191] [important]** — `tryReadSocketLayerFrames` uses `tryReadTQueue` with `orElse`, but `tryReadTQueue` returns `Nothing` instead of retrying when a queue is empty, so the alternatives are not checked. For example, when `preferFrontend` is true and `frontendQ` is empty, queued backend or TaskProcessor frames are ignored by this drain attempt. Fix: explicitly chain on `Nothing` (`tryReadTQueue preferred >>= maybe next ...`) or use a helper that tests all queues in the requested order.

### Pattern Violations
- None beyond the drain-loop correctness issues above.

### Test Gaps
- Step 3 is still pending; add coverage that proves mixed frontend/backend/TaskProcessor queues drain fairly and that backend status/notify frames are processed while frontend traffic is present.

### Suggestions
- Consider making `drainSocketLayerFrames` return `SocketLayerFrames` rather than `Maybe SocketLayerFrames`, since the current blocking `readTQueue` alternatives never return `Nothing`.
