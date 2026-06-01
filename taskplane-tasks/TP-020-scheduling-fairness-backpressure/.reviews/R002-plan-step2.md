## Plan Review: Step 2: Implement tests and scheduling/backpressure improvements

### Verdict: APPROVE

### Summary
The Step 2 plan is aligned with the approved Step 1 contract: it focuses on bounded `scheduleTasks` coverage for burst distribution, saturated-worker backpressure, and all-saturated overflow while keeping production-capacity scheduling out of scope. The implementation scope is appropriately minimal for `SimpleServer`, and the smoke assertion plan avoids overfitting nondeterministic multi-worker timing while preserving existing retry/liveness behavior.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- Consider carrying forward R001's optional load-score preference test for multiple idle workers with unequal CPU/memory scores, so the capacity/backpressure patch cannot accidentally drop the existing least-loaded-worker behavior.
- When writing the scheduler tests, assert both assignment pairs and `tasksLeft` contents/order so overflow re-enqueue behavior remains compatible with `TaskProcessor`.
