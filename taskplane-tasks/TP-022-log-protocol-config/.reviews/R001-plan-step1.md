## Plan Review: Step 1: Design protocol compatibility boundary

### Verdict: APPROVE

### Summary
The plan identifies the new log protocol/config surface, makes the types public through `Lotos.Zmq`, and explicitly keeps the existing `WorkerLogging` PUB/SUB frames unchanged until a later transport switch. It also calls out defaulted JSON parsing so existing broker/worker configs can continue to decode, which addresses the key compatibility boundary for this step.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- When implementing, pin the exact `LogBatch`/`LogAck` multipart frame order in comments and frame tests, and keep `WorkerLogging` tests unchanged as a compatibility guard.
- Make the default values visible in code/tests, using existing `broker.json` and `worker.json` shapes as backward-compatibility fixtures.
- Ensure `LogEvent` carries the sequence/gap metadata needed by the TP mission so drop policies never hide lost log lines.
