## Code Review: Step 3: Protect ordering and lifecycle behavior

### Verdict: REVISE

### Summary
No project-declared typecheck/lint/format-check commands are configured in `.pi/taskplane-config.json`, and there is no `package.json` fallback. I ran `cabal build lotos`, `cabal test lotos:test:test-zmq-worker-frames --test-show-details=direct`, and `cabal test lotos:test:test-zmq-worker-wake --test-show-details=direct`; all passed. However, the R010 gap is only partially addressed: one new ordering/wake helper is test-only and is not used by the migrated `LBW` backend path, so the tests still would not fail if the actual worker enqueue/wake behavior regressed.

### Issues Found
1. **[lotos/src/Lotos/Zmq/LBW.hs:346] [important]** — `handleWorkerBackendFrames` still performs `enqueueTS` and `notifyTaskWakeSignal` inline instead of using the newly tested `enqueueBackendTaskAndNotify` helper. As a result, `workerBackendEnqueueNotifiesAfterTaskIsQueued` only verifies dead/test-only code, not the actual migrated backend receive path required by Step 3 and called out in R010. Fix by routing `BackendTaskFrames` through the shared helper (or by exposing/testing `handleWorkerBackendFrames` via a bounded harness) so a future enqueue-before-wake regression in `LBW` fails the test.
2. **[lotos/test/ZmqWorkerFrames.hs:239] [important]** — The heartbeat/status forwarding test still drives `sendWorkerBackendFrames` with a test endpoint and manually forwards `statusFrames`; it does not exercise `sendWorkerBackendFramesOrStop`, the real `workerBackendDealerEndpoint`, or `InternalTaskStatusFrames` handling in `LBW`. This leaves the Step 3 heartbeat/status lifecycle guarantee under-protected despite the STATUS claim that migrated LBW paths are covered. Add a small harness around the real handler/drain path, or extract a shared forwarding helper used by `LBW` and assert forwarded heartbeat/status frames plus stopped-loop failure behavior through that path.

### Pattern Violations
- `enqueueBackendTaskAndNotify` is currently exported production code but only used by tests; avoid introducing test-only production helpers unless the production path actually calls them.

### Test Gaps
- No regression currently fails if `LBW.handleWorkerBackendFrames` notifies before enqueueing or stops forwarding internal task-status frames through its real endpoint.

### Suggestions
- Keep the inproc EventLoop smoke tests; they are useful protocol checks once the actual LBW helper/handler path is also covered.
