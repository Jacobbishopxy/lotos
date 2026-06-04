## Plan Review: Step 1: Design LogIngest EventLoop ownership

### Verdict: APPROVE

### Summary
The revised plan addresses the R001 blocker by avoiding the built-in EventLoop `Mailbox` drop path and using a lightweight `Callback` plus LogIngest-owned bounded STM queue for observable overload accounting. It also covers the required endpoint/ACK path decisions, keeps decode/journal/retention work off the EventLoop callback, and preserves ROUTER routing-id plus `LogBatch`/`LogAck` frame ordering.

### Issues Found
None.

### Missing Items
- None blocking.

### Suggestions
- When implementing, make sure the `withEventLoopIn` bracket lives for the entire LogIngest ingestion-loop lifetime; returning the existing `ThreadId` must not let the EventLoop bracket exit immediately and stop the ROUTER owner.
- Consider naming the overload/malformed-frame counters distinctly from journal-malformed accounting so `/logs/stats` does not conflate protocol dispatch failures with journal replay corruption.
