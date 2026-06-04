## Code Review: Step 3: Add tests

### Verdict: REVISE

### Summary
The new targeted suites compile and pass, and there are no configured typecheck/lint/format-check commands in `.pi/taskplane-config.json` or `package.json` to run. However, the added regressions do not actually exercise the reservation lifecycle paths that Step 3 was required to lock down: the tests manually apply/release the overlay instead of proving TaskProcessor reconciliation and SocketLayer terminal/stale release behavior.

### Issues Found
1. **[applications/TaskSchedule/test/Scheduler.hs:105] [important]** — The “non-terminal status and stale heartbeat” regression bypasses the behavior it is meant to protect. It constructs an already adjusted worker with `reservationAdjustedWorker 1`, so it would still pass if `reconcileWorkerReservations` incorrectly dropped reservations after a heartbeat/status update. Add coverage that starts with real reservation state plus a worker status snapshot and proves reconciliation keeps broker-known occupied capacity for non-terminal/unsafe heartbeat cases.
2. **[lotos/test/ZmqCapacityReservations.hs:13] [important]** — The terminal/stale release tests only verify the low-level map deletion helpers, not release on `TaskSucceed`, `TaskFailed`, or stale-worker recovery integration. This misses the stated Step 3 requirement to test reservation release on success/failure/stale recovery; these tests would pass even if SocketLayer stopped calling `deleteTSWorkerReservationByTask` or TaskProcessor stopped deleting reservations for stale workers. Add deterministic lifecycle tests around the status handlers/recovery path, or expose/test a small lifecycle helper that distinguishes non-terminal retention from success, failure, and stale-worker release.

### Pattern Violations
- None.

### Test Gaps
- Missing actual conservative reconciliation coverage for retained reservations across non-terminal task status or stale heartbeat snapshots.
- Missing actual success/failure/stale-worker release coverage beyond raw map operations.

### Suggestions
- Targeted verification run during review: `cabal test lotos:test:test-zmq-capacity-reservations TaskSchedule:test:test-scheduler` passed.
