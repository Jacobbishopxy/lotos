## Code Review: Step 3: Add regression coverage

### Verdict: REVISE

### Summary
The targeted worker frame/log transport suites pass, and there were no configured static typecheck/lint/format commands in `.pi/taskplane-config.json` or `package.json` to run. However, two Step 3 regression outcomes are not actually locked by the added tests: the worker logging loop's stopped-loop classification is bypassed, and the actual `TaskAcceptorAPI.taSendTaskStatus` callback path from R007 is not exercised.

### Issues Found
1. **[lotos/test/ZmqWorkerLogTransport.hs:157] [important]** — The logging stopped-loop test only proves that raw `Zmqx.EventLoop.sends`/`recv` return `Left` after a bracketed loop has stopped. It does not exercise `workerLogLoop`/`handleWorkerLogLoopError`, so a regression that retries forever or logs incorrectly on `ETERM` would still pass. Fix: add a bounded harness that drives the worker log loop (or a small exported/internal test helper around the loop error handler) with a stopped EventLoop and asserts it terminates instead of retrying.
2. **[lotos/test/ZmqWorkerFrames.hs:349] [important]** — The R007 callback regression is marked complete, but the test invokes the public `sendTaskStatus` helper, not the actual `TaskAcceptorAPI.taSendTaskStatus` IO callback path created in `mkWorkerService` (`LBW.hs:173-179`). That callback has distinct behavior because it runs from task execution code and re-enters `LotosApp` for failure logging via the captured environment. Fix: add a custom acceptor/harness or narrow test hook that invokes `taSendTaskStatus` after `workerBackendRunning` is false and asserts it returns within the timeout.

### Pattern Violations
- `Lotos.Zmq` now exposes `markWorkerBackendStoppedForTest` in the public facade (`lotos/src/Lotos/Zmq.hs:121`). Prefer keeping test-only lifecycle hooks behind an internal/test support module rather than adding `ForTest` API to the main user-facing surface.

### Test Gaps
- No assertion verifies the failed-delivery log path for stopped task-status callbacks; at minimum the callback should be exercised, with log capture optional if this project lacks a logger test harness.

### Suggestions
- The added forked-action teardown test is useful. Consider making child-thread registration/cancellation robust to async exceptions in a follow-up, since `forkIO` and MVar registration currently are not masked as one atomic operation.

Verification run: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-worker-log-transport` passed. `git diff --check` passed. No configured static quality commands were available.
