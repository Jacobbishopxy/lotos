## Code Review: Step 3: Add regression coverage

### Verdict: APPROVE

### Summary
The R009/R010 blocking gaps have been addressed: the regression suite now drives the production `TaskAcceptorAPI.taSendTaskStatus` path, exercises the worker log loop stopped-EventLoop classification, preserves the two-field `LotosEnv` surface, and waits for forked `LotosApp` children during `runZmqApp` teardown. No static typecheck/lint/format commands are configured in `.pi/taskplane-config.json`, and there is no `package.json`; `git diff --check`, the targeted worker frame/log transport tests, and `cabal build all --enable-tests` all pass.

### Issues Found
None.

### Pattern Violations
- None blocking. `workerLogLoopStep` is exported from the exposed `Lotos.Zmq.LBW.LogTransport` module to support tests; it is not re-exported from the main `Lotos.Zmq` facade, but consider treating it as an internal/testing helper in a future API cleanup.

### Test Gaps
- The stopped logging-loop test currently hits the ACK-drain/recv stopped path before any pending batch exists. The implementation handles stopped sends too, but a second test with an enqueued pending log event would lock that branch more directly.
- The callback regression asserts that `taSendTaskStatus` returns promptly after worker shutdown; it does not assert the stopped-backend failure log/no-enqueue behavior. That is acceptable for this step, but log capture would make the regression stronger.

### Suggestions
- Make `forkApp` registration async-exception-safe in a follow-up (for example, mask around fork/register or use `forkFinally`) so an exception between `forkIO` and registry insertion cannot leave an untracked child.

Verification run: `git diff --check 3667d496ff114a8a7ecc7839d2b47697c44b8a41..HEAD`; `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-worker-log-transport`; `cabal build all --enable-tests`.
