## Code Review: Step 2: Implement aligned config/defaults

### Verdict: APPROVE

### Summary
The implementation aligns the TaskSchedule entry points with the MVP runtime contract: server and worker now accept zero/one config arguments, client reuses the exported `readClientConfig`, and defaults/sample JSON use frontend `5555`, backend `5556`, and reserved logging `5557`. No configured `.pi`/`package.json` typecheck, lint, or format-check commands were present; I additionally ran `cabal build TaskSchedule:exe:ts-server TaskSchedule:exe:ts-worker TaskSchedule:exe:ts-client`, which passed (`Up to date`).

### Issues Found
None.

### Pattern Violations
None.

### Test Gaps
- The explicit sample config files were not runtime-smoke-tested here; Step 3 should still exercise/inspect the explicit-config path or otherwise confirm the JSON examples load as intended.

### Suggestions
- Documentation still contains the old README caveat about inverted worker addresses, but that is already scheduled for Step 4 rather than a blocker for this implementation step.
