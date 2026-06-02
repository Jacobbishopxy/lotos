## Plan Review: Step 2: Implement worker transport switch

### Verdict: APPROVE

### Summary
The Step 2 checklist is terse, but together with the approved Step 1 semantics it covers the required transport switch: bounded/non-blocking worker enqueue, separate DEALER LogBatch send/ACK handling, preservation of task log meaning, broker LogIngest wiring, and focused ACK/retry/drop tests. I previously flagged timeout/sequence ambiguity in R001; the R002/R003-approved notes in `STATUS.md:77-80` now provide enough implementation constraints for this step.

### Issues Found
- None.

### Missing Items
- None.

### Suggestions
- When implementing `STATUS.md:38`, make the split logging endpoint explicit in defaults/demo configs so `logIngestRouterEnabled` does not keep skipping the ROUTER when `logIngestAddr == infoStorage.loggingAddr`.
- Preserve public callback compatibility deliberately: either keep `taPubTaskLogging` as a compatibility wrapper that enqueues `LogEvent`s or add a new callback with a migration path, and map existing `STDOUT`/`STDERR` prefixes plus final command results to stable `LogStream`/`LogLevel` values.
- Prefer extracting the bounded buffer/drop and ACK retry state machine behind fakes so the planned tests can cover partial ACK progress, rejection-without-progress, and broker outage retry without slow ZMQ integration.
