## Code Review: Step 1: Design the client path

### Verdict: APPROVE

### Summary
Only `STATUS.md` changed for this step; no executable or library code was modified. The design notes align with `docs/task-schedule-mvp.md`: required `TASK_JSON`, optional `CLIENT_CONFIG_JSON`, no new dependencies, non-zero failure exits, and ACK-only success semantics. Static quality checks were skipped because no `.pi` task-runner config or `package.json` scripts are present in this worktree.

### Issues Found
None.

### Pattern Violations
- None.

### Test Gaps
- None for this design/status-only step. The implementation review should still verify timeout-field equality, ACK timeout behavior, and the required Cabal builds.

### Suggestions
- Carry forward the plan-review suggestions during Step 2, especially verifying `reqTimeoutSec` units for `mkClientService`/`Z_RcvTimeO` and converting parse/ZMQ failures into clear stderr messages.
