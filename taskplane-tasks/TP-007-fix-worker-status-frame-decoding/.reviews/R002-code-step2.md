## Code Review: Step 2: Implement decode/handling fix

### Verdict: APPROVE

### Summary
The implementation applies the planned minimal fix: the worker DEALER routing id is now set from `workerId` before connecting, so the backend ROUTER prepends a UTF-8 worker id frame that `RouterBackendIn` can decode while preserving payload frame order. The added inproc ROUTER/DEALER regression covers the critical frame shape and decoding path. No configured typecheck/lint/format-check commands were available in `.pi/taskplane-config.json`, and there is no `package.json`; I additionally ran `cabal test lotos:test:test-zmq-worker-frames` and `git diff --check`, both passing.

### Issues Found
None.

### Pattern Violations
- None.

### Test Gaps
- End-to-end TaskSchedule verification that `/SimpleServer/worker_stats` contains `simpleWorker_1` is still pending in Step 3, not blocking this implementation step.

### Suggestions
- Consider validating or documenting `workerId` constraints in a future change, since ZeroMQ routing ids must be valid socket identities and should remain unique per backend.
