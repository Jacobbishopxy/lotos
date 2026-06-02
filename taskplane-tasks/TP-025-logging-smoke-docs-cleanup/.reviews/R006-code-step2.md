## Code Review: Step 2: Cleanup obsolete logging coupling

### Verdict: APPROVE

### Summary
The R005 blocker is addressed: `runLBS` now starts LogIngest unconditionally and the obsolete same-address guard/export is gone. `/info` is now scheduler-only while `/logs/*` continues to read from LogIngest state. No configured typecheck/lint/format-check commands were present in `.pi/taskplane-config.json` and there is no `package.json`; supplemental `git diff --check` and `cabal test lotos:test:test-zmq-log-ingest lotos:test:test-zmq-log-protocol-config` both passed.

### Issues Found
None.

### Pattern Violations
- None.

### Test Gaps
- None blocking for this step.

### Suggestions
- When Step 4 updates the broader docs, remove the remaining README/MVP/logging-redesign references to `/info.workerLoggingsMap` so users do not follow the removed compatibility path.
