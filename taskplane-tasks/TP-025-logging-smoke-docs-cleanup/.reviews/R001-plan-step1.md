## Plan Review: Step 1: Update end-to-end smoke expectations

### Verdict: APPROVE

### Summary
The plan targets the required migration of both smoke scripts from legacy `/info.workerLoggingsMap` evidence to deterministic `/logs` API evidence. It covers per-worker current-run stdout/result assertions, captures `/logs/recent` and `/logs/stats`, and limits stats checks to deterministic zero-loss/non-empty/worker-count conditions.

### Issues Found
- None.

### Missing Items
- None.

### Suggestions
- Keep the smoke assertions anchored to the generated `RUN_ID` and exact worker IDs so cached or unrelated log entries cannot satisfy the checks.
- If adding JSON parsing beyond `grep`, update the scripts' prerequisite checks accordingly; otherwise prefer simple stable-key assertions to avoid new runtime assumptions.
