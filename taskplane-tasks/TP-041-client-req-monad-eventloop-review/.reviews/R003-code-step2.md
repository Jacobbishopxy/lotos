## Code Review: Step 2: Implement selected client path

### Verdict: APPROVE

### Summary
The implementation follows the approved direct monadic REQ path: `sendTaskRequest` now uses `reqTimeoutSec` for a bounded ACK receive and maps timeout/decode failures to `Nothing` without changing the public API or ACK frame ordering. The TaskSchedule client correctly removes the duplicate outer `System.Timeout` now that the library call owns ACK wait semantics. No configured typecheck/lint/format-check commands exist in `.pi/taskplane-config.json` and there is no `package.json`; I spot-verified with `cabal test lotos:test:test-zmq-client-ack-frames` and `cabal build TaskSchedule:exe:ts-client`, both passing.

### Issues Found
- None.

### Pattern Violations
- None.

### Test Gaps
- None blocking. The new unit test covers a silent bound router timeout; Step 3's planned smoke test should still verify live client submission through the server/worker path.

### Suggestions
- Consider documenting in Step 4 that the public client timeout is now enforced inside `sendTaskRequest`, so downstream users do not need to wrap the API with their own ACK receive timeout.
