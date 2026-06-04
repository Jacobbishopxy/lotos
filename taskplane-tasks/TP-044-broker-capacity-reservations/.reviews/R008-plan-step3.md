## Plan Review: Step 3: Add tests

### Verdict: REVISE

### Summary
The Step 3 plan covers the main happy-path test outcomes: repeated scheduling before heartbeat catch-up, terminal/stale release, and multi-worker fairness. However, it does not explicitly carry forward the key R006/R007 regression risk: non-terminal `TaskPending`/`TaskProcessing` updates and conservative heartbeat reconciliation must not free or erase broker-known occupied capacity before terminal status/stale recovery.

### Issues Found
1. **[Severity: important]** — Add an explicit test outcome for the R006 regression: a worker with existing occupied slots receives a newly dispatched/reserved task, then reports `TaskPending`/`TaskProcessing` and/or a heartbeat that accounts only for older work; a subsequent scheduling pass must still treat the new task as occupying capacity and must not over-assign. Without this, Step 3 can miss the exact conservative-reconciliation failure that Step 2 had to fix. Suggested fix: add a checkbox/test case for “non-terminal status and stale heartbeat do not release reservations; only terminal status or stale-worker recovery does.”

### Missing Items
- Regression coverage for conservative heartbeat reconciliation after non-terminal task-status updates, especially unknown-baseline or preserved-baseline occupancy from R006/R007.

### Suggestions
- Keep the existing release tests, but assert both sides of the lifecycle: no release on non-terminal status/unsafe heartbeat, release on success/failure/stale recovery.
