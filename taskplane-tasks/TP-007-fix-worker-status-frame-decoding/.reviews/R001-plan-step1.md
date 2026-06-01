## Plan Review: Step 1: Diagnose frame shape mismatch

### Verdict: APPROVE

### Summary
The diagnosis matches the code path: `LBW.socketLoop` sends worker status payload frames on the worker DEALER, while `SocketLayer.handleWorkerMessage` decodes the backend ROUTER-prepended first frame as a `Text` `RoutingID`. The planned fix to set the DEALER `Z_RoutingId` from `WorkerServiceConfig.workerId` before connecting is minimal and preserves the existing `WorkerReportStatus`, `WorkerReportTaskStatus`, and `RouterBackendIn` payload ordering.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- In implementation, encode `workerId` explicitly to the `ByteString` expected by `Z_RoutingId` and keep the option set before `Zmqx.connect`.
- A small regression around decoding `[workerId, WorkerStatusT, ack, worker-state...]` would be useful if practical without long-running sockets.
