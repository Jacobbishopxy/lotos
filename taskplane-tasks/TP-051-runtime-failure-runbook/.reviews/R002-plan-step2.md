## Plan Review: Step 2: Write safe recovery procedures

### Verdict: APPROVE

### Summary
The Step 2 plan covers the required recovery-procedure outcomes from PROMPT.md: stuck/stale workers, LogIngest backlog semantics, broker overload without lossy queue advice, capacity reservation underutilization, and smoke failure triage. It also aligns with the Step 1 taxonomy already present in `runtime-failures.md`, so the worker has a concrete evidence map to build safe diagnosis/remediation guidance from.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- When writing the procedures, keep the recovery ordering explicit: collect endpoint/log evidence first, then scale/restart/resubmit only with task idempotency and incident notes captured.
- For broker overload, prefer language around reducing submission rate, adding workers/capacity, and investigating slow drains; avoid any wording that implies clearing or dropping task/status handoff queues is safe.
