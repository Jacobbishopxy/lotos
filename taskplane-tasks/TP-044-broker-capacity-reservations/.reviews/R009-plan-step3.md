## Plan Review: Step 3: Add tests

### Verdict: APPROVE

### Summary
The revised Step 3 plan now covers the prompt's required test outcomes: repeated scheduling before heartbeat catch-up, reservation release on terminal/stale paths, and multi-worker fairness. It also addresses the prior R008 blocker by explicitly adding regression coverage that non-terminal status or stale heartbeat updates must not release broker-known occupied capacity before terminal status or stale recovery.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- When implementing the tests, prefer assertions that prove both sides of the lifecycle in the same scenario where practical: no release on `TaskPending`/`TaskProcessing` or unsafe heartbeat, then release on success/failure/stale recovery.
