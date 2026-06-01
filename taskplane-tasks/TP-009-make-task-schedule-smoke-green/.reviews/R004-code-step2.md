## Code Review: Step 2: Tighten smoke script/docs if needed

### Verdict: APPROVE

### Summary
The Step 2 change removes the stale `KNOWN_ACK_BLOCKER`/exit-2 branch so a missing client ACK is now a hard smoke failure, while preserving the existing marker and garbage checks. The README and MVP doc now agree on PASS/FAIL exit behavior and record the current TP-009 green evidence. No configured typecheck/lint/format-check commands were present in `.pi/taskplane-config.json`, and there is no `package.json`; I ran `bash -n scripts/task-schedule-smoke.sh`, which passed.

### Issues Found
None.

### Pattern Violations
- None.

### Test Gaps
- None for this Step 2 tightening; the full smoke rerun remains covered by Step 3's verification gate.

### Suggestions
- Consider aligning the script's top-of-file exit-code comment and PASS `detail` string with the docs by mentioning worker stats and the no-current-run-garbage check in addition to ACK and marker proof.
