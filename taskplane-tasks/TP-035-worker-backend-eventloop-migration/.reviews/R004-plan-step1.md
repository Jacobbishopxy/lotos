## Plan Review: Step 1: Design worker backend EventLoop ownership

### Verdict: APPROVE

### Summary
The revised design addresses the prior R001-R003 blockers: status traffic is no longer gated behind backend waits, EventLoop mailbox drop semantics are avoided for loss-sensitive frames, and callbacks remain nonblocking via unbounded `TQueue` handoff. The plan now defines the worker backend endpoint names, internal PAIR handling, heartbeat wait strategy, context ownership, and stopped-loop behavior sufficiently for Step 2 implementation.

### Issues Found
None.

### Missing Items
None.

### Suggestions
- When implementing the “small status-drain slice” from `STATUS.md:32`, pick a named constant/commented value so future reviewers can tell the intended latency/heartbeat tradeoff.
- Preserve the existing backend DEALER routing-id setup before handing the socket to the EventLoop; it is easy to lose during ownership refactoring and is required for broker worker identity semantics.
