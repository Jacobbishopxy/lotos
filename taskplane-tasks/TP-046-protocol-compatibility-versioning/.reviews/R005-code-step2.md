## Code Review: Step 2: Harden tests/docs

### Verdict: APPROVE

### Summary
The Step 2 changes align with the approved compatibility policy: the scheduler suite now pins the exact `WorkerState` 9-frame shape, verifies the old 8-frame fallback defaults `taskCapacity` to 1, and rejects unsupported trailing frames. The mdBook chapter, SUMMARY link, README invariant, and TaskSchedule MVP cross-reference cover append-only rules, fallback expectations, deliberate break criteria, and version-tag deferral. Static quality checks were not configured (`.pi/taskplane-config.json` has no relevant commands and there is no `package.json`); I ran `cabal test TaskSchedule:test:test-scheduler`, which passed.

### Issues Found
- None.

### Pattern Violations
- None.

### Test Gaps
- None blocking. Broader protocol/frame suites and `cabal build all --enable-tests` remain correctly deferred to Step 3.

### Suggestions
- None.
