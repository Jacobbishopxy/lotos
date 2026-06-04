## Plan Review: Step 3: Document contributor verification

### Verdict: APPROVE

### Summary
The Step 3 plan directly covers the required documentation outcomes: README contributor commands, the mdBook verification profile, and conditional AGENTS.md review/update. This is sufficient for the task mission, especially after Steps 1-2 have already established and validated the Makefile CI targets that the docs need to describe.

### Issues Found
None.

### Missing Items
None.

### Suggestions
- In README, replace or qualify the current `cabal test all` quickstart guidance with `make ci-check` so contributors are not directed toward long-running demo/server suites by default.
- In the mdBook chapter, prefer naming the profile commands (`make ci-check`, `make ci-test`, `make smoke-single`, `make smoke-multi`) and pointing detailed suite membership back to the Makefile to reduce future documentation drift.
