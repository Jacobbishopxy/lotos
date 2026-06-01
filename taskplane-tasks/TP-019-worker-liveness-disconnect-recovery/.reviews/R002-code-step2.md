## Code Review: Step 2: Implement recovery logic

### Verdict: APPROVE

### Summary
The implementation adds broker-side liveness tracking, recovers stale workers before scheduler snapshots, and routes recovered in-flight tasks through the existing retry/garbage semantics. No configured static quality commands were declared in `.pi/taskplane-config.json`, but `cabal build all --enable-tests` and `cabal test lotos:test:test-zmq-worker-frames` both passed.

### Issues Found
None.

### Pattern Violations
- None.

### Test Gaps
- No direct processor-loop integration test asserts that `scheduleTasks` never sees stale worker statuses, but the helper tests cover stale detection, map removal, retry readiness, garbage handling, and succeeded-task dropping.

### Suggestions
- Consider documenting the new `taskProcessor.workerStaleTimeoutSec` knob during Step 4 since it is observable configuration.
