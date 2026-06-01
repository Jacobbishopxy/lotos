## Plan Review: Step 1: Define fairness/backpressure contract

### Verdict: APPROVE

### Summary
The contract in `STATUS.md` is concrete and aligned with the TP-020 mission: it defines a conservative per-pass capacity model from the state TaskSchedule actually reports, preserves load-score ordering, and keeps overflow tasks queued through `tasksLeft`. The bounded unit-test plan covers the main regressions for burst distribution and backpressure, while explicitly documenting that full `parallelTasksNo`-aware scheduling is follow-up debt rather than part of this demo-scope change.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- Consider adding one small scheduler test for the existing load-score preference when multiple idle workers are eligible, since the contract explicitly says lower CPU/memory load wins and the proposed tests mostly exercise equal-load fairness and saturation behavior.
