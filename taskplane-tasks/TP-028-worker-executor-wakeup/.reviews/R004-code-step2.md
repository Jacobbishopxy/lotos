## Code Review: Step 2: Implement wake-on-enqueue and cleanup

### Verdict: APPROVE

### Summary
The implementation meets the Step 2 outcomes: task enqueue now sends a coalescing wake signal, the executor checks the queue before blocking instead of sleeping for 10 seconds, and the broker poll-loop `putStrLn` is removed. I found no protocol/frame-order changes or regressions to status/log transport paths. No configured typecheck/lint/format-check commands were declared in `.pi/taskplane-config.json`, and there is no `package.json`; targeted verification `cabal test lotos:test:test-zmq-worker-wake` passed.

### Issues Found
None.

### Pattern Violations
- None.

### Test Gaps
- None blocking for this step; broader worker lifecycle/build/smoke verification remains scheduled for Step 3.

### Suggestions
- Consider validating `parallelTasksNo > 0` in worker config in a future cleanup; invalid zero/negative values were already unsafe, but the new blocking helper makes that configuration debt more visible.
