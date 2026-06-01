## Code Review: Step 2: Implement tests and scheduling/backpressure improvements

### Verdict: APPROVE

### Summary
The scheduler change implements the approved conservative capacity contract: only idle workers are eligible, assignments are capped to one task per eligible worker per pass, and overflow stays in `tasksLeft` for re-enqueue. The new `test-scheduler` suite covers equal-worker burst splitting, busy/waiting backpressure, all-saturated overflow, and least-loaded ordering. No configured typecheck/lint/format commands were present in `.pi/taskplane-config.json` and there is no `package.json`; I additionally verified `cabal build all --enable-tests` and `cabal test TaskSchedule:test:test-scheduler` both pass.

### Issues Found
None.

### Pattern Violations
- None.

### Test Gaps
- None blocking. The deterministic scheduler boundary is covered; leaving exact multi-worker smoke distribution out remains consistent with the approved plan.

### Suggestions
- Consider assigning UUIDs in scheduler fixtures with `fillTaskID'` in a future cleanup so tests mirror the production task-ID invariant more closely, even though the current scheduler logic does not inspect IDs.
