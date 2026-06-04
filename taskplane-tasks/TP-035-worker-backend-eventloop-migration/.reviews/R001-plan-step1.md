## Plan Review: Step 1: Design worker backend EventLoop ownership

### Verdict: REVISE

### Summary
The plan identifies stable endpoint names, avoids EventLoop callbacks, and keeps status callbacks from directly touching the backend DEALER. However, its proposed blocking `EventLoop.recv` on only the backend mailbox can delay or drop internal task-status frames, which does not preserve the current poll-on-either-socket behavior.

### Issues Found
1. **[Severity: important]** — The planned loop waits on `worker-backend-dealer` with the full heartbeat timeout before draining `worker-backend-status-pair` (`STATUS.md:32`). `EventLoop.recv` waits on one mailbox endpoint only, and EventLoop mailboxes drop newest frames when full (`EventLoop.hs:124-127`, `EventLoop.hs:621-628`), while the current direct poll wakes on either backend or internal PAIR readiness (`LBW.hs:244-260`). Fix: revise the design to prevent status traffic from being gated by backend-task receives, e.g. drain both mailboxes nonblocking each iteration and use a short bounded slice/min timeout, or otherwise provide a wake/select strategy that handles internal PAIR messages promptly and defines how full-mailbox drops are avoided or surfaced.

### Missing Items
- A concrete lifecycle policy for backend EventLoop failure/stopped-loop while task callbacks can still send to the local PAIR; logging `send`/`recv` errors is not enough to show whether the worker stops, pauses status reporting, or prevents silent status loss.

### Suggestions
- Consider tying mailbox capacities to existing worker/socket backpressure configuration or documenting why `64` is sufficient for task and status bursts.
- Explicitly mention `withEventLoopIn` using the `LotosApp` ZMQ context, matching the TP-034 ownership pattern.
