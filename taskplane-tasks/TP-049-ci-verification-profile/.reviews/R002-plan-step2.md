## Plan Review: Step 2: Implement CI-friendly targets and optional workflow

### Verdict: APPROVE

### Summary
The Step 2 plan covers the required outcomes: finalize CI-safe Makefile targets, keep smoke checks explicit opt-in, decide whether to add a GitHub Actions workflow, and run the aggregate CI target. Given `.github/` is not currently present in this worktree, the "add or explicitly defer" workflow criterion is an appropriate outcome-level plan rather than over-prescribing repository policy.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- If deferring a workflow, record the reason in STATUS.md or the later contributor docs so the optional workflow decision is visible to future maintainers.
- When running `make ci-check`, call out any external tool prerequisites such as `mdbook` separately from Cabal/package failures.
