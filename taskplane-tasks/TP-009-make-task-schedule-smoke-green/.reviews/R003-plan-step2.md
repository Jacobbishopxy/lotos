## Plan Review: Step 2: Tighten smoke script/docs if needed

### Verdict: APPROVE

### Summary
The Step 2 plan targets the right follow-up from the green Step 1 evidence: remove the obsolete known-ACK-blocker/exit-2 path so ACK regressions fail hard, and update smoke documentation/evidence wording without weakening checks. This aligns with the task requirement to keep exit codes documented and avoid papering over product failures.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- When updating docs, make sure `scripts/task-schedule-smoke.sh`, `docs/task-schedule-mvp.md`, and `README.md` all agree that the normal statuses are now PASS/FAIL and that stale TP-005/TP-007/TP-008 blocker text is removed or replaced with the current TP-009 evidence.
