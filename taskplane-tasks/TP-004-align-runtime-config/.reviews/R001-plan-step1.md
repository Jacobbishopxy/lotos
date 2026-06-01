## Plan Review: Step 1: Plan runtime wiring

### Verdict: APPROVE

### Summary
The plan matches the MVP runtime contract: frontend/client on `5555`, worker/backend on `5556`, reserved worker logging on `5557`, and optional JSON config paths with built-in defaults. It also identifies the right minimal implementation areas, including exporting the existing config readers through the public facade so the TaskSchedule executables can reuse them.

### Issues Found
None.

### Missing Items
None.

### Suggestions
- When implementing the facade export, note that `Lotos.Zmq.Config` is currently an internal `other-module`, so adding `readBrokerConfig`, `readWorkerConfig`, and `readClientConfig` to `Lotos.Zmq` is the least invasive way to reuse the existing readers.
- Keep sample config filenames and README commands aligned so users can immediately run the documented default and explicit-config flows.
