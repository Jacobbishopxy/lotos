## Plan Review: Step 2: Live dashboard rendering

### Verdict: REVISE

### Summary
I reviewed `PROMPT.md` and `STATUS.md`, but could not find a Step 2 implementation plan beyond the three high-level STATUS checkboxes. Those checkboxes mirror the task outcomes, but they do not state how the live endpoint data will be mapped into the dashboard or how offline/partial-error rendering will be preserved, so the plan is not yet reviewable enough for this live-rendering step.

### Issues Found
1. **[Severity: important]** — The plan does not identify the live-data-to-UI mapping needed to satisfy Step 2. Add a concise plan covering which fields drive each required diagnostic: heartbeat age/stale state from `info.workerLivenessMap`, reservations from `info.workerReservationMap`, queue overload from `info.runtimeQueueStats`, worker capacity from `/worker_stats`, task queues/worker assignments from `/tasks` and `/worker_tasks`, and LogIngest counters from `/logs/stats`.
2. **[Severity: important]** — The plan does not describe loading/error/offline behavior beyond the STATUS checkbox. Step 1’s fallback currently appears all-or-nothing; Step 2 should explicitly preserve useful sample/offline rendering when the server is unavailable and state how non-disruptive indicators will distinguish live, loading, and fallback/error states.

### Missing Items
- A short rendering approach that keeps the existing light responsive layout while replacing the static TP-056 arrays with derived live/sample snapshot data.
- A verification intent for this step, at minimum a dashboard build after wiring and a no-server/offline preview check; live-server manual verification can remain in Step 4 if not practical here.

### Suggestions
- Keep `/logs/stats` visually separate from `runtimeQueueStats` so operators do not confuse LogIngest rejected/drop accounting with task/status handoff queue overload.
