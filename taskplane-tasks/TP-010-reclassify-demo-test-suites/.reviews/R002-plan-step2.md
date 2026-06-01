## Plan Review: Step 2: Apply test metadata/code/docs changes

### Verdict: APPROVE

### Summary
The Step 2 plan follows the approved classification from Step 1 and should satisfy the task goal: keep the assertion-based suites as Cabal tests, reclassify demo/long-running/server suites as runnable demos, and update docs/context to make the safe verification posture explicit. The planned `ConcExecutor` non-zero HUnit exit handling plus `cabal test all`/`cabal build all --enable-tests` documentation addresses the main CI-hang risk without deleting demos.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- Carry forward the R001 suggestions during implementation: include `demo-logger` in the documented demo commands and verify/fix `demo-conc-executor2`'s relative `../scripts/*` paths for the documented working directory.
- Consider updating `hie.yaml` if component names there become stale after converting old `lotos:test:*` demo suites to `lotos:exe:demo-*` components.
