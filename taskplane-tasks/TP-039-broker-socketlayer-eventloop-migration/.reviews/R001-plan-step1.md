## Plan Review: Step 1: Design broker EventLoop topology

### Verdict: REVISE

### Summary
The endpoint naming and send-through-`EventLoop.sends` policy are mostly clear and align with the migration goal. However, the proposed built-in `Mailbox` receivers leave a documented silent-drop path for task/status traffic, which directly conflicts with the Step 1 requirement.

### Issues Found
1. **[Severity: important]** — `STATUS.md:81-83` chooses `Zmqx.EventLoop.Mailbox` for the frontend ROUTER, backend ROUTER, and TaskProcessor receiver PAIR, while `PROMPT.md:65-67` requires defining failure behavior such that task/status traffic is not silently dropped. The current `EventLoop` API explicitly drops newest messages when a mailbox is full (`EventLoop.hs:124-127`) and discards the `tryWriteMailbox` result (`EventLoop.hs:472-474`), so “large capacity” plus “draining quickly” cannot prove no silent loss. Revise the plan to use a no-silent-loss handoff for these critical inbound paths, e.g. `Callback` receivers that only enqueue complete frame sets into SocketLayer-owned unbounded STM queues (matching the TP-035 task/status precedent), or bounded callback queues with explicit overflow observability and fail-stop/logged transport failure semantics. Do not leave this as a residual overload risk for task/status traffic.

### Missing Items
- A deterministic mailbox/callback overflow policy for critical inbound broker traffic: frontend client task frames, backend worker status/task-status frames, and TaskProcessor worker-dispatch frames.

### Suggestions
- Keep the proposed stable endpoint names and `EventLoop.sends` wrappers for ACKs, worker dispatch, and scheduler notifications; those parts are well-scoped and should make Step 2 reviewable.
