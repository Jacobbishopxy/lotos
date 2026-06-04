## Plan Review: Step 1: Define the CI-safe command set

### Verdict: APPROVE

### Summary
The step plan aligns with the task mission: it inventories registered tests/demos, defines CI-safe Makefile targets, keeps long-running smoke/demo workflows out of the default path, and validates target syntax with dry-runs. This is sufficient for Step 1 as an outcome-level plan; implementation details can be resolved while editing the Makefile.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- When inventorying, make sure both Cabal packages are covered: `lotos` regression test suites and TaskSchedule's `test-worker-lifecycle` / `test-scheduler`, while keeping `demo-*` executables and smoke scripts explicit opt-in.
- A good CI-safe shape would be `ci-build` = compile all packages/tests, `ci-test` = explicit terminating suites, `ci-docs` = `book-build`, and `ci-check` = the aggregate routine command.
