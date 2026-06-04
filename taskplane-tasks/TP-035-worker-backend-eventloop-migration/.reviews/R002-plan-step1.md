## Plan Review: Step 1: Design worker backend EventLoop ownership

### Verdict: REVISE

### Summary
The revised plan fixes the R001 polling/waiting concern and now defines stable endpoint names, `withEventLoopIn` context ownership, short bounded waits, and a stopped-loop policy. One blocking gap remains: the design still accepts silent `Mailbox 64` overflow on loss-sensitive task and status traffic, which is not equivalent to the current direct-poll transport semantics.

### Issues Found
1. **[Severity: important]** — The plan relies on fixed `Mailbox 64` receivers and says overflow will be “surfaced by tests/logging” (`STATUS.md:32`), but the current EventLoop implementation silently discards a newest message when a mailbox is full (`EventLoop.hs:124-127`, `EventLoop.hs:472-480`). That can silently lose backend task frames or internal task-status frames during a burst or while the socket-loop is busy gathering/sending heartbeat status, violating the task’s requirement to keep enqueue/status semantics intact. Fix: define a concrete overflow-safe policy before implementation, such as proving and testing a hard maximum burst below capacity, adding an observable overflow/fatal-stop path, or choosing a design that keeps loss-sensitive frames in ZMQ/backpressured queues instead of a silently dropping mailbox.

### Missing Items
- A concrete, implementable mailbox-overflow policy for both `worker-backend-dealer` task frames and `worker-backend-status-pair` status frames.

### Suggestions
- The bounded wait/drain strategy and stopped-loop shutdown policy are good revisions; keep those in the implementation plan once the overflow policy is made explicit.
