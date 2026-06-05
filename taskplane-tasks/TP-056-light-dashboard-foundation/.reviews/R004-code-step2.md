## Code Review: Step 2: Makefile and README wiring

### Verdict: APPROVE

### Summary
The Makefile now exposes the requested dashboard install/build/dev/preview targets via `npm --prefix applications/dashboard`, and `make help` advertises them. The README documents the dashboard location, static/sample-data scope, light Linear-inspired direction, and root commands. No project typecheck/lint/format-check commands are configured in `.pi/taskplane-config.json`, and there is no root `package.json`; I ran `make help`, target dry-runs, and `git diff --check` instead, all successfully.

### Issues Found
None.

### Pattern Violations
- None.

### Test Gaps
- None for this wiring step; Step 3 already covers running `make dashboard-build` after dependency installation.

### Suggestions
- Consider widening the Makefile help label column (for example from `%-16s` to `%-18s`) so the longer `dashboard-install` entry stays visually aligned with the rest of the table.
- The README layout comment for `Makefile` still says "Cabal convenience targets"; it could be broadened to mention dashboard/npm targets too.
