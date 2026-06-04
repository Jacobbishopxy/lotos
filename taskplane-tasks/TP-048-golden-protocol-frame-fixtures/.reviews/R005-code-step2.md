## Code Review: Step 2: Add golden protocol tests

### Verdict: APPROVE

### Summary
The added tests cover exact in-code golden frame shapes for client requests/ACKs, worker task/status/task-status payloads, log batches/ACKs, and the TaskSchedule `WorkerState` append-only fallback through both bare payload and backend status wrapper decoding. I found no blocking correctness issues. No typecheck/lint/format commands were configured in `.pi/taskplane-config.json`, and there is no `package.json`; targeted protocol tests and `git diff --check` passed.

### Issues Found
None.

### Pattern Violations
None.

### Test Gaps
None blocking. Verified with `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-client-ack-frames lotos:test:test-zmq-log-protocol-config TaskSchedule:test:test-scheduler` and `git diff --check c832432..HEAD`.

### Suggestions
- Consider checking specific parse-error constructors/messages in a few negative tests if future diagnostics become part of the compatibility contract; current left/right assertions are sufficient for this step.
