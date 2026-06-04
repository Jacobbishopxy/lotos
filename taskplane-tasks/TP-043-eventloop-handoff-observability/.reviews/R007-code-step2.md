## Code Review: Step 2: Implement non-dropping metrics

### Verdict: APPROVE

### Summary
The R006 linearizability concern is addressed for the production enqueue/dequeue paths by updating the queue and its metric TVar inside the same STM transaction. No configured typecheck/lint/format commands were available (`.pi/taskplane-config.json` has no testing commands and there is no `package.json`); the project-specific targeted build `cabal build lotos lotos:test:test-zmq-worker-frames TaskSchedule:exe:ts-worker` passed. The implementation preserves no-drop queue semantics while exposing broker `/info` snapshots and worker reporter snapshots.

### Issues Found
None.

### Pattern Violations
- None found.

### Test Gaps
- Step 3 still needs direct regression coverage for enqueue/drain/high-water stats and for keeping LogIngest drop/reject accounting distinct from no-drop task/status metrics.

### Suggestions
- Consider making stale-worker recovery use a stats-aware helper in a future cleanup so every failed-queue enqueue path follows the same centralized pattern, even though the current recovered count no longer has the permanent drift race from R004/R006.
