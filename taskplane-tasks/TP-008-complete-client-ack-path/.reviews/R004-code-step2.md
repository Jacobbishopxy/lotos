## Code Review: Step 2: Implement ACK response path

### Verdict: APPROVE

### Summary
The implementation matches the approved ROUTER/REQ ACK plan: frontend requests are decoded with the correlated request-id envelope, tasks are assigned IDs and enqueued before the broker replies, and the reply preserves the REQ correlation frames so the client receives a single `Ack` body frame. Declared static quality checks were not configured in `.pi/taskplane-config.json` and there is no `package.json`; as additional verification, `cabal build lotos`, `cabal test lotos:test:test-zmq-client-ack-frames`, and `git diff --check` all passed.

### Issues Found
- None.

### Pattern Violations
- None.

### Test Gaps
- No blocking gaps for Step 2. The full runtime `ts-client` smoke remains in the planned Step 3 verification.

### Suggestions
- Since `RouterFrontendIn`/`RouterFrontendOut` constructors are exported and their request-id field changed from `Text` to raw `ByteString`, note that API-shape change in delivery notes/docs.
