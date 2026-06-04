## Code Review: Step 3: Add regression coverage

### Verdict: REVISE

### Summary
The R009 gaps are partly addressed: the added tests now drive `TaskAcceptorAPI.taSendTaskStatus` through a live worker harness and exercise the worker log loop stopped-EventLoop path, and the targeted Cabal suites pass. However, the forked-action lifecycle hardening is not yet sufficient for the stated teardown guarantee, and the implementation introduces a source-breaking change to the public `LotosEnv` record API.

### Issues Found
1. **[lotos/src/Lotos/Logger.hs:85] [important]** — `cancelForkedAppThreads` only sends `killThread` to registered children and then lets `runAppWithContext` return, so it does not wait for forked `LotosApp` actions to finish before the ZMQ context bracket tears down. The added test waits for `childStopped` *after* `runZmqApp` has returned, which still allows the child action/finalizers to outlive context teardown. Fix: track forked actions with completion notification (for example `forkFinally` plus an `MVar`, or `Async`) and cancel then wait for termination in `runAppWithContext` before returning; adjust the test so the child is known stopped when `runZmqApp` returns.
2. **[lotos/src/Lotos/Logger.hs:56] [important]** — Adding `lotosChildThreads` to the exported `LotosEnv (..)` record is source-breaking for downstream users that construct or pattern-match `LotosEnv` from the public `Lotos.Logger`/`Lotos.Zmq` API. This task should not require a public environment-constructor migration. Fix: preserve the public construction surface (for example by hiding/internalizing the new lifecycle state behind helper constructors, avoiding export of the raw constructor in a planned API change, or otherwise providing a backward-compatible compatibility path).

### Pattern Violations
- None beyond the public API compatibility issue above.

### Test Gaps
- The logging stopped-loop test currently takes the stopped `recv`/ACK-drain path before any pending batch exists; it still would not catch a send-branch regression. Consider enqueueing a pending log event before stopping the EventLoop or adding a second step test for stopped `sends`.

### Suggestions
- No configured static quality commands were available in `.pi/taskplane-config.json`, and there is no `package.json`. Verification run: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-worker-log-transport` passed.
