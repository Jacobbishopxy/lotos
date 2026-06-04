## Plan Review: Step 1: Inventory unbounded handoff queues

### Verdict: APPROVE

### Summary
The Step 1 inventory covers the relevant worker and broker EventLoop handoff queues, distinguishes protocol-critical no-drop queues from bounded LogIngest drop/reject semantics, and chooses measurable depth/high-water fields with throttled warning behavior. The exposure plan is consistent with the prompt: broker stats become visible through `/info`, LogIngest remains under `/logs/stats`, and worker-side visibility is provided without extending TaskSchedule protocol frames.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- When implementing the `WorkerInfo` exposure, be mindful that `WorkerInfo` is exported publicly; document any added fields and avoid forcing protocol-frame changes for existing TaskSchedule reporters.
