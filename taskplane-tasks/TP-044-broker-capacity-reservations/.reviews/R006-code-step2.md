## Code Review: Step 2: Implement reservation accounting

### Verdict: REVISE

### Summary
The implementation adds a broker-owned reservation map and applies it to scheduler snapshots, and the targeted build `cabal build lotos TaskSchedule:exe:ts-server` passes. No configured typecheck/lint/format commands were declared in `.pi/taskplane-config.json` and there is no `package.json` fallback. However, the reconciliation path treats unknown reservation baselines as zero, which can clear non-terminal occupancy too early and reintroduce over-assignment.

### Issues Found
1. **[lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs:303] [important]** — `reconcileWorkerReservationList` uses `maximum (0 : mapMaybe wcrBaselineOccupiedSlots reservations)`, so reservations whose baseline is `Nothing` are reconciled as if their dispatch baseline were `0`. `handleOtherTaskStatus` creates exactly those `Nothing` reservations for `TaskPending`/`TaskProcessing` at `SocketLayer.hs:500-503`; on a worker that already had occupied slots, a heartbeat that only accounts for the pre-existing work can therefore remove the new task's reservation before terminal status. That violates the conservative R002 lifecycle and can let the scheduler over-assign again. Fix: keep unknown-baseline reservations unreconciled until terminal/stale recovery, or preserve the original dispatch baseline when converting a reservation after `TaskPending`/`TaskProcessing`; reconcile only the subset with a known baseline.

### Pattern Violations
- None beyond the blocking reservation lifecycle issue above.

### Test Gaps
- Step 3 has not started yet; add a regression where a worker has existing occupied slots, receives a new reserved task, reports `TaskProcessing`, and then a heartbeat with only the old occupied count does not clear the new reservation.

### Suggestions
- Consider moving the `TaskPending`/`TaskProcessing` reservation mutation until after confirming the task exists in `workerTasksMap`, to avoid capacity leaks from duplicate or late non-terminal status frames for unknown tasks.
