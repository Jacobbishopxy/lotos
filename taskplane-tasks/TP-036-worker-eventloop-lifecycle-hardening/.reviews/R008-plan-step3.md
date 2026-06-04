## Plan Review: Step 3: Add regression coverage

### Verdict: APPROVE

### Summary
The revised Step 3 plan now covers the lifecycle regression outcomes required by the prompt: backend and logging stopped-loop behavior, log mailbox/drop visibility without applying lossy semantics to task/status traffic, and forked action teardown. It also carries forward the R007/R006 gap by explicitly planning a `taSendTaskStatus`/`sendTaskStatus` stopped-backend regression around the `workerBackendRunning` guard, so the critical nonblocking status-callback path should be proven.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- Keep the stopped-loop and teardown tests bounded with short timeouts so hangs fail fast and are easy to diagnose.
