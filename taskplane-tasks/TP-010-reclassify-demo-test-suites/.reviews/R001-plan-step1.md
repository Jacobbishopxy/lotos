## Plan Review: Step 1: Plan test classification

### Verdict: APPROVE

### Summary
The plan correctly distinguishes assertion-based, bounded regression suites from no-assertion demos and long-running/server examples. Reclassifying the five demo-style suites as runnable `demo-*` executables while keeping the three bounded HUnit suites as tests should make `cabal test all` safe after implementation and preserve `cabal build all --enable-tests` as the full compile gate.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- Ensure the final docs include or explicitly defer `demo-logger` alongside the other reclassified demo executables, preferably with a `timeout` example because it intentionally runs for about 50 seconds.
- When documenting `demo-conc-executor2`, validate its current relative `../scripts/*` helper paths under the documented working directory, or adjust the command/code so the preserved demo is actually runnable from the stated location.
