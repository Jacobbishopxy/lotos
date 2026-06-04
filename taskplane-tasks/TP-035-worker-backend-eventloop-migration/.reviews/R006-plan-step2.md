## Plan Review: Step 2: Implement EventLoop-backed worker backend loop

### Verdict: APPROVE

### Summary
The Step 2 plan is sufficiently grounded in the approved Step 1 design: backend DEALER ownership moves behind `EventLoop`, inbound backend/internal PAIR frames are handed off through non-dropping STM queues, and parsing/enqueue/wake/status-forwarding stays on the worker socket-loop thread. The plan also preserves the important lifecycle/cadence constraints from prior reviews: prompt draining of both traffic sources, existing enqueue-before-wake ordering, periodic heartbeat timing, explicit-context `withEventLoopIn`, and fail-stop handling for backend send failures.

### Issues Found
None.

### Missing Items
None.

### Suggestions
- Keep the Step 1 wording authoritative over the Step 2 checkbox phrase “via mailbox”: avoid `EventLoop.Mailbox` for task/status frames and use the approved callback-to-`TQueue` handoff to prevent drop-on-full behavior.
- Preserve the worker DEALER routing id setup before registering the socket with the EventLoop, since broker identity semantics depend on it.
