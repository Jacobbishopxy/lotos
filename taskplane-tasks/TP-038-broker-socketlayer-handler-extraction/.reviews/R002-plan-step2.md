## Plan Review: Step 2: Extract behavior-preserving helpers

### Verdict: APPROVE

### Summary
The Step 2 plan follows the approved Step 1 boundaries and covers the required behavior-preserving extractions: frontend enqueue/ACK, backend worker status/task-status handling, retry/garbage disposition, scheduler notification, and worker-task dispatch map updates. It explicitly keeps socket mechanics at the receive/send wrappers and proposes callbacks for outbound effects, which should make the later EventLoop seam cleaner without changing multipart frame ordering.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- Keep callback-based helpers free of unnecessary `FromZmq`/`ToZmq` constraints where the wrapper already handles decoding/encoding; this will make the extracted business logic easier to review.
- During implementation, preserve the current ordering for side effects: enqueue before client ACK, backend send before `workerTasksMap` append, and load-balancer notification after retry/garbage or status-map mutation.
