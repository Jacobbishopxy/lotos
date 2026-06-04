## Code Review: Step 2: Implement EventLoop-owned SocketLayer

### Verdict: REVISE

### Summary
The R003 recursion and `tryReadTQueue`/`orElse` defects have been fixed, and `cabal build lotos` reports `Up to date`. No declared typecheck/lint/format-check commands are configured in `.pi/taskplane-config.json`, and there is no `package.json` fallback. However, the new drain preference still is not fair across all three broker queues, so TaskProcessor dispatch frames can starve under sustained frontend and backend traffic.

### Issues Found
1. **[lotos/src/Lotos/Zmq/LBS/SocketLayer.hs:178] [important]** — `drainQueuedSocketLayerFrames` alternates only between frontend-first and backend-first order, and `tryReadSocketLayerFrames` never makes `taskProcessorFrames` the preferred queue. If frontend and backend queues are both continuously non-empty, every batch selects frontend/backend alternately and queued TaskProcessor frames are never drained, so scheduled worker-task dispatch can be delayed indefinitely. Fix: rotate across all three queue priorities (frontend, backend, TaskProcessor) or otherwise guarantee TaskProcessor is selected within a bounded number of drained frames; ideally carry a three-way preference/order rather than a `Bool`.

### Pattern Violations
- None beyond the queue fairness issue above.

### Test Gaps
- Step 3 should include a mixed-queue regression where frontend, backend, and TaskProcessor queues are all populated and the drain loop proves TaskProcessor dispatch is processed despite sustained frontend/backend traffic.

### Suggestions
- Consider deriving the next drain preference from the frame just handled, so the blocking read's frontend bias does not reset every batch.
