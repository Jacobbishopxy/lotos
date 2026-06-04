## Plan Review: Step 2: Implement selected client path

### Verdict: APPROVE

### Summary
The Step 1 decision recorded in `STATUS.md` gives a concrete and appropriate Step 2 implementation direction: keep the client REQ path direct/monadic, use the existing `reqTimeoutSec` as the bounded ACK wait, and return `Nothing` on ACK timeout rather than letting `zmqUnwrap` crash. This fits the current `LBC.hs`/TaskSchedule client shape and preserves the stated routing-id and ACK frame-order constraints without adding unnecessary EventLoop ownership.

### Issues Found
- None.

### Missing Items
- None.

### Suggestions
- Add or extend a client ACK-frame regression to cover the timeout/no-ACK path so Step 3 proves `sendTaskRequest` returns `Nothing` instead of throwing.
- Consider removing the TaskSchedule client's outer `System.Timeout` once `sendTaskRequest` owns the bounded receive semantics, to avoid two overlapping timeout mechanisms.
