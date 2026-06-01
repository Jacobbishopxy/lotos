## Code Review: Step 2: Implement retry delay behavior

### Verdict: APPROVE

### Summary
The implementation follows the approved retry-delay model: failed retries are wrapped with readiness metadata, positive intervals are filtered out before scheduling, non-positive intervals remain immediate, and exhausted retries still use the existing garbage path. JSON/ZMQ task frame shapes remain unchanged, and info storage projects retry envelopes back to plain tasks. No declared static typecheck/lint/format commands are configured in `.pi/taskplane-config.json` and no `package.json` exists; I additionally ran `cabal test lotos:test:test-zmq-worker-frames` successfully (9 cases).

### Issues Found
- None.

### Pattern Violations
- None.

### Test Gaps
- No blocking gaps. The new bounded tests cover positive-delay eligibility, zero/negative immediate behavior, and mixed partitioning; a later integration test could exercise the full `TaskProcessor` queue path if desired.

### Suggestions
- Keep the exported retry helper follow-up tied to the existing TP-016 API-tightening debt so the public facade can be narrowed if internal tests are later moved off `Lotos.Zmq`.
