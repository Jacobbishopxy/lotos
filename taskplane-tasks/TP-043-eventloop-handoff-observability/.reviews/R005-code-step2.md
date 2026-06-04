## Code Review: Step 2: Implement non-dropping metrics

### Verdict: REVISE

### Summary
The R004 stale-recovery overcount issue is addressed in production code by returning the exact recovered retry count and recording that count. However, a touched regression test was not updated for the changed `recoverStaleWorkers` return type, so the targeted worker-frame test suite no longer builds. Project config declares no typecheck/lint/format commands and there is no `package.json`; additionally, `cabal build lotos` and `cabal build TaskSchedule:exe:ts-worker` passed, while `cabal build lotos:test:test-zmq-worker-frames` failed as below.

### Issues Found
1. **[lotos/test/ZmqWorkerFrames.hs:591] [important]** — `cabal build lotos:test:test-zmq-worker-frames` fails because `recoverStaleWorkers` now returns `([RoutingID], Int)`, but the test still binds the whole tuple as `staleWorkerIds` and compares it to `[testWorkerId]`. Sample error: `Couldn't match expected type: ([RoutingID], Int) with actual type: [RoutingID]` at line 593. Fix by destructuring the tuple, e.g. `(staleWorkerIds, recoveredRetryCount) <- recoverStaleWorkers ...`, then assert `staleWorkerIds @?= [testWorkerId]` and `recoveredRetryCount @?= 1`.

### Pattern Violations
- None found.

### Test Gaps
- Step 3 still needs direct coverage for enqueue/drain/high-water behavior and for keeping no-drop metrics distinct from LogIngest drop/reject accounting.

### Suggestions
- Consider adding an assertion for the new recovered retry count in the existing stale-worker recovery test so the R004 fix is protected directly.
