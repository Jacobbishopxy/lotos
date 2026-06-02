## Code Review: Step 1: Update end-to-end smoke expectations

### Verdict: APPROVE

### Summary
The smoke-script changes satisfy Step 1 by moving logging proof from `/info.workerLoggingsMap` to `/logs/worker/<workerId>` plus clean `/logs/stats` assertions, and they capture `/logs/recent`/`/logs/stats` snapshots without adding new dependencies. No configured typecheck/lint/format-check commands were present in `.pi/taskplane-config.json` and there is no `package.json`; supplemental `bash -n scripts/task-schedule-smoke.sh scripts/task-schedule-multi-worker-smoke.sh` and `git diff --check` both passed.

### Issues Found
- None.

### Pattern Violations
- None.

### Test Gaps
- Full smoke execution was not run during this review; Step 3 already requires `scripts/task-schedule-smoke.sh` and `scripts/task-schedule-multi-worker-smoke.sh`.

### Suggestions
- Consider updating the single-worker script header comment to mention the new `/logs` evidence requirement, matching the multi-worker header.
- If you want the STATUS note's “accepted events are non-empty” proof to be explicit, add an `"acceptedEvents":` nonzero check; the current worker/task-count checks already imply accepted events for the default scenarios.
