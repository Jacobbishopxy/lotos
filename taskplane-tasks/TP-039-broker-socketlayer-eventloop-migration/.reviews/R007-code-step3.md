## Code Review: Step 3: Strengthen protocol and scheduler coverage

### Verdict: APPROVE

### Summary
The added broker SocketLayer regression covers the Step 3 risk areas: enqueue-before-ACK, worker status/liveness, TaskProcessor dispatch while frontend/backend traffic is queued, retry/garbage handling, and notification traffic. No configured typecheck/lint/format-check commands were present in `.pi/taskplane-config.json` and there is no `package.json` fallback; I ran `git diff --check bd83f3b..HEAD` and the targeted protocol suites `cabal test lotos:test:test-zmq-client-ack-frames lotos:test:test-zmq-worker-frames --test-options='--hide-successes'`, all passing.

### Issues Found
1. None.

### Pattern Violations
- None.

### Test Gaps
- None blocking.

### Suggestions
- Consider avoiding the new public facade exports of `TaskSchedulerData` and `runSocketLayer` (`lotos/src/Lotos/Zmq.hs:97`, `lotos/src/Lotos/Zmq.hs:108`) if they are only for tests; a dedicated exposed test/internal module would keep `Lotos.Zmq` focused on the supported public API.
- The new notify-path assertions decode `Notify` successfully; if this protocol grows beyond its current single-frame ACK shape, add an exact `@?= toZmq ...` frame comparison similar to the worker dispatch assertion.
