## Plan Review: Step 1: Design reservation model

### Verdict: REVISE

### Summary
The revised plan now identifies a broker-owned reservation map and describes the broad scheduler API compatibility strategy, addressing much of R001. However, the lifecycle rules still release capacity too early: clearing reservations on any heartbeat or on `TaskProcessing` can re-open worker slots before the heartbeat snapshot actually reflects the dispatched/processing task, which is exactly the over-assignment window this task must close.

### Issues Found
1. **[Severity: important]** — The plan treats every worker heartbeat as authoritative and clears that worker's outstanding reservations, but heartbeats can be stale relative to recently dispatched tasks: the worker may report before receiving/enqueuing the task, or before its `WorkerInfo` waiting/processing counters have caught up. Fix: make heartbeat release conditional on the snapshot demonstrably accounting for the reserved capacity, or keep broker-side occupancy/reservations until a safer lifecycle point.
2. **[Severity: important]** — Releasing a reservation on `TaskProcessing` without also counting broker-known non-terminal task-map entries in the adjusted scheduler snapshot can undercount capacity until the next heartbeat. `handleOtherTaskStatus` notifies the load balancer immediately, so a scheduling pass can run with the old `workerStatusMap`, no reservation, and the task merely marked `TaskProcessing` in `workerTasksMap`. Fix: specify that adjusted snapshots include broker-known in-flight/processing occupancy after reservation release, or do not release the capacity reservation on `TaskProcessing` until heartbeat/terminal status makes it safe.

### Missing Items
- A conservative rule for reconciling reservations with heartbeat snapshots that may lag broker dispatches or worker queue counter updates.
- An explicit statement of what capacity signal replaces a reservation after `TaskProcessing` if reservations are released before terminal status.

### Suggestions
- Model the overlay as “broker-known occupied slots not yet safely reflected in the scheduler input,” not only as unobserved dispatches; then terminal success/failure and stale recovery are straightforward release points while heartbeat reconciliation can remain conservative.
