## Code Review: Step 3: Protect ordering and lifecycle behavior

### Verdict: REVISE

### Summary
`cabal build lotos` passed, and the targeted worker frame/wake suites pass. No project-declared typecheck/lint/format-check commands are configured in `.pi/taskplane-config.json`, and there is no `package.json` fallback. The lifecycle logging change is reasonable, but the new Step 3 tests mostly exercise raw `Zmqx.EventLoop` behavior rather than the migrated `LBW.socketLoop`/drain/forwarding paths, so they do not yet protect the ordering and lifecycle guarantees this step is meant to lock down.

### Issues Found
1. **[lotos/test/ZmqWorkerFrames.hs:160] [important]** — The new task ordering test only verifies that an EventLoop callback writes received DEALER frames into a local `TQueue`; it never exercises `LBW.handleWorkerBackendFrames`/`socketLoop`, so it would still pass if the migrated worker stopped enqueueing tasks, notified wake before enqueue, or regressed the bounded/fair drain ordering. Fix by adding coverage around the actual worker backend drain/handle path (for example by extracting a testable helper or running a bounded worker socket-loop harness) and asserting enqueue order plus wake-on-enqueue.
2. **[lotos/test/ZmqWorkerFrames.hs:196] [important]** — The status/heartbeat test manually calls `EventLoop.sends` and manually forwards `statusFrames`, so it does not cover `sendWorkerBackendFrames`, the real `workerBackendDealerEndpoint`, heartbeat emission from `socketLoop`, or task-status forwarding from `InternalTaskStatusFrames`. This misses the Step 3 requirement to protect task-status forwarding, heartbeat behavior, and stopped-loop handling after the migration. Add tests that drive the migrated LBW forwarding/heartbeat paths directly, including a queued-backend-frame scenario so the R007/R008 fairness guarantee remains protected.

### Pattern Violations
- None.

### Test Gaps
- The existing `test-zmq-worker-wake` coverage still only proves the wake primitive/queue helper behavior, not wake-on-enqueue as performed by the EventLoop-backed worker backend receive path.

### Suggestions
- Keep the lightweight inproc EventLoop tests as protocol smoke coverage, but add at least one regression that would fail if `drainWorkerBackendFrames` stopped alternating status/backend queues or if `sendWorkerBackendFrames` swallowed a stopped-loop error.
