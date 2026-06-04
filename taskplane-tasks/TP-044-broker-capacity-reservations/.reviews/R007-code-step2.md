## Code Review: Step 2: Implement reservation accounting

### Verdict: APPROVE

### Summary
The R006 blocking issue has been addressed: unknown-baseline reservations are no longer reconciled as baseline-zero, and non-terminal status handling now preserves an existing dispatch baseline while avoiding leaks for unknown task IDs. No configured typecheck/lint/format commands are present in `.pi/taskplane-config.json` and there is no `package.json` fallback; as an additional narrow build check, `cabal build lotos TaskSchedule:exe:ts-server` passes.

### Issues Found
None.

### Pattern Violations
- None found.

### Test Gaps
- Step 3 has not started yet; add deterministic coverage for repeated scheduling before heartbeat catch-up, terminal/stale release, and the R006 regression around unknown-baseline non-terminal occupancy.

### Suggestions
- Consider a later refinement so a `TaskPending`/`TaskProcessing` frame that arrives after a reservation was already safely reconciled from a heartbeat does not recreate a conservative unknown-baseline overlay and temporarily underutilize capacity until terminal status.
