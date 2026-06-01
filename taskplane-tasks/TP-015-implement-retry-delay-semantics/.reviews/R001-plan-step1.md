## Plan Review: Step 1: Design retry-delay model

### Verdict: APPROVE

### Summary
The proposed design covers the required timing semantics: exhausted retries still go to garbage, remaining retries are decremented before requeue, non-positive intervals remain immediate, and positive intervals become eligible only after a recorded not-before time. Keeping readiness metadata in an internal failed-queue envelope preserves existing `Task` JSON/ZMQ frame compatibility, and the planned fixed-time helper tests are appropriately bounded.

### Issues Found
- None.

### Missing Items
- None.

### Suggestions
- Clarify in the implementation/docs that `taskRetryInterval` is interpreted in seconds, matching the surrounding timeout/config conventions.
- When implementing the failed-queue envelope, ensure not-yet-due retries are retained/re-enqueued without passing to `scheduleTasks`, and avoid a queue-head delayed item starving later ready retries.
