## Code Review: Step 2: Implement cleanup

### Verdict: APPROVE

### Summary
The implementation wires the selected logging stance end-to-end: server info storage now binds the configured `5557` logging endpoint, workers publish a worker-id topic plus the existing `WorkerLogging` payload, and the info snapshot preserves accumulated ring buffers. The smoke script and docs were updated to require current-run logging evidence, and I found no blocking correctness issues. No declared typecheck/lint/format commands are configured in `.pi/taskplane-config.json` and there is no `package.json`; I additionally ran `cabal build lotos TaskSchedule:exe:ts-server TaskSchedule:exe:ts-worker` and `bash -n scripts/task-schedule-smoke.sh`, both passing.

### Issues Found
None.

### Pattern Violations
- None.

### Test Gaps
- None blocking for this step; the smoke path now asserts worker logging evidence. Full build/test/smoke execution remains scheduled for Step 3.

### Suggestions
- Consider parsing `logging-info.json` structurally in the smoke helper in a future pass if `jq` or a project-local JSON assertion helper becomes available; the current grep checks are acceptable for the fresh single-run smoke topology.
