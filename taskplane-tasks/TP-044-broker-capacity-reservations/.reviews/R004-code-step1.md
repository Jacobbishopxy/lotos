## Code Review: Step 1: Design reservation model

### Verdict: APPROVE

### Summary
The only codebase change is the Step 1 STATUS.md design record. It now addresses the prior R002 blockers by retaining broker-known non-terminal occupancy through `TaskProcessing` and by making heartbeat reconciliation conservative rather than blindly clearing reservations. Quality checks were not run because `.pi/taskplane-config.json` declares no relevant typecheck/lint/format commands and there is no `package.json` fallback.

### Issues Found
None.

### Pattern Violations
- None.

### Test Gaps
- Not applicable for this design-only step; implementation/test coverage is scoped to later steps.

### Suggestions
- Consider updating the Step 2 checklist wording that still says reservations are released on `processing` so it does not conflict with the R002-final design that capacity remains occupied until terminal status or safe reconciliation.
