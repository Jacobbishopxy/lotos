## Plan Review: Step 1: Design worker backend EventLoop ownership

### Verdict: REVISE

### Summary
The plan now addresses the earlier R001/R002 concerns around endpoint names, status wait fairness, stopped-loop policy, and avoiding the built-in dropping `Mailbox` receiver mode. However, the new callback-to-blocking-`TBQueue` overflow policy creates a different blocking lifecycle hazard in the EventLoop worker, so the design still does not satisfy the lightweight-callback requirement safely.

### Issues Found
1. **[Severity: important]** — The proposed callbacks use blocking `writeTBQueue` when the 1024-frame queue fills (`STATUS.md:32,38-39`), but `Callback` handlers run on the single EventLoop worker thread and are required to be quick/nonblocking (`EventLoop.hs:129-133`). If the EventLoop worker blocks in such a callback, it cannot process queued `EventLoop.sends` commands; those sends synchronously wait for the worker reply (`EventLoop.hs:551-578`). That can deadlock the worker socket-loop when it tries to forward an internal task-status or heartbeat through the same backend EventLoop while an inbound task/status queue is full, and it can also prevent clean bracket shutdown because `stopEventLoop` waits for the worker to finish (`EventLoop.hs:390-399`). Fix: revise the overflow/backpressure design so EventLoop callbacks never block indefinitely, e.g. use a nonblocking handoff with an explicit fatal/observable overflow path, keep the draining thread independent from synchronous sends, or otherwise prove that send waits cannot occur while a callback is blocked.

### Missing Items
- A concrete overflow/backpressure policy that preserves loss-sensitive task/status semantics without blocking the EventLoop callback thread or creating a send/shutdown deadlock.

### Suggestions
- Keep the R001 fixes (drain both inbound sources promptly with bounded waits) and the explicit stopped-loop policy; only the full-queue callback behavior needs redesign.
