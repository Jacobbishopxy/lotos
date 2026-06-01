## Plan Review: Step 1: Design smoke approach

### Verdict: REVISE

### Summary
The revised STATUS now addresses the R001 gaps: it names the cabal commands, readiness probes, cleanup strategy, and known ACK-blocker handling. One proof issue remains: the marker-file check is not tied to the current smoke run, so the script could pass using stale output from a previous run.

### Issues Found
1. **[Severity: important]** — `STATUS.md:97-100` polls `.tmp/task-schedule-demo.out` and treats `task-schedule-ok` as completion proof, but the design never removes the file before the run or uses a per-run unique marker path. `docs/task-schedule-mvp.md:213` explicitly clears this marker in the manual acceptance flow. Add a pre-run `rm -f .tmp/task-schedule-demo.out` (or generate a unique marker path inside `.tmp/task-schedule-smoke/` and embed it in the task JSON) so marker proof cannot be satisfied by stale evidence.
2. **[Severity: important]** — `STATUS.md:97-99` relies on HTTP readiness alone after starting background `cabal run` processes. If an old server is already bound to `8081`/`5555` or the newly spawned server/worker exits early, the readiness probes could hit the old service and still proceed. Add process-liveness checks for the tracked server/worker PIDs during readiness, and fail with preserved logs if a spawned process exits before its readiness criterion is met.

### Missing Items
- Fresh-run evidence guard for the marker file and smoke evidence directory.
- Spawned-process health checks as part of readiness/pass-fail criteria.

### Suggestions
- Consider recording a small run ID in the task content/log filenames so endpoint snapshots and garbage checks can be correlated to the current submission.
