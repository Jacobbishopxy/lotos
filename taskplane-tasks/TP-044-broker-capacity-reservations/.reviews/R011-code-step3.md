## Code Review: Step 3: Add tests

### Verdict: REVISE

### Summary
The new reconciliation and SocketLayer release helper coverage is a good improvement, and targeted verification passes (`cabal test lotos:test:test-zmq-capacity-reservations` and `cabal test TaskSchedule:test:test-scheduler`). There are no configured typecheck/lint/format-check commands in `.pi/taskplane-config.json`, and no `package.json` fallback. However, the stale-worker release requirement is still only covered by a thin helper that the production stale recovery path does not call, so the test would not catch a regression in the actual TaskProcessor cleanup path.

### Issues Found
1. **[lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs:185] [important]** — Stale-worker reservation release is still performed directly with `deleteTSWorkerReservation`, while the new test exercises `releaseWorkerReservations` in isolation (`lotos/test/ZmqCapacityReservations.hs:65`). This means Step 3's stale-recovery coverage would still pass if the TaskProcessor stale-worker cleanup were accidentally removed or changed, so it does not lock down the stated release-on-stale-recovery behavior. Fix by routing the TaskProcessor stale-worker cleanup through the shared lifecycle helper and/or adding a deterministic stale recovery test that invokes the same production cleanup path after `recoverStaleWorkers` identifies stale workers.

### Pattern Violations
- None.

### Test Gaps
- Stale-worker reservation release is not yet covered through the production TaskProcessor stale recovery path or a helper actually used by that path.

### Suggestions
- The internal module exposure is acceptable for targeted tests, but consider keeping the helper explicitly documented as internal-only if later API docs are generated.
