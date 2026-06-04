## Code Review: Step 2: Extract behavior-preserving helpers

### Verdict: APPROVE

### Summary
The SocketLayer refactor cleanly extracts decoded frontend, backend dispatch, worker status, and task-status handling while preserving the original send/enqueue/map/notify ordering. The requested baseline-vs-HEAD diff is empty because these changes are still uncommitted on HEAD, so I reviewed the working-tree diff for `SocketLayer.hs` and `STATUS.md`.

Quality checks: no declared typecheck/lint/format commands were configured in `.pi/taskplane-config.json`, and there is no `package.json` fallback. I additionally ran `cabal build lotos`, `cabal test lotos:test:test-zmq-client-ack-frames`, and `cabal test lotos:test:test-zmq-worker-frames`; all passed/returned up to date.

### Issues Found
- None.

### Pattern Violations
- None.

### Test Gaps
- None blocking for this extraction step. The existing client ACK and worker frame regression suites pass.

### Suggestions
- Consider removing now-redundant constraints such as `FromZmq t` on `handleClientRequest` and `FromZmq w` on `handleWorkerStatusUpdate` in a cleanup pass; this is non-blocking and does not affect behavior.
