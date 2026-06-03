## Plan Review: Step 1: Design EventLoop transport boundary

### Verdict: REVISE

### Summary
The plan correctly identifies the intended high-level boundary: keep retry/drop state in `WorkerLogTransport` and move DEALER socket ownership behind a `Zmqx.EventLoop` transceiver. However, it does not yet satisfy two explicit Step 1 outcomes: choosing mailbox vs callback ACK delivery with shutdown behavior, and defining the regression tests that prove independent ACK receipt and socket ownership safety.

### Issues Found
1. **[Severity: important]** — ACK delivery is still underspecified. STATUS only says ACKs should be consumed via the EventLoop receiver path, but Step 1 requires deciding whether this is `Mailbox` polling or `Callback` delivery. Fix: choose the delivery mode and document its consequences (mailbox capacity/drop behavior and timeout mapping, or callback threading/nonblocking/exception behavior) before implementation.
2. **[Severity: important]** — Shutdown/lifecycle behavior is missing. `Zmqx.EventLoop.withEventLoop` is bracket-scoped and stops public `sends`/`recv` callers with a stopped-loop error after exit, while the current `runWorkerLogTransport` API returns a forked `ThreadId`. Fix: define where the EventLoop bracket lives, how the logging loop exits or is killed with the worker service, and how stopped-loop/send/recv errors are handled without touching the DEALER directly.
3. **[Severity: important]** — The test plan is not concrete enough to prove the required behavior. Step 1 asks for tests showing ACKs can arrive independently of send retries and socket ownership is not violated, but no specific scenarios or affected tests are named. Fix: add explicit coverage such as an EventLoop-backed transport integration test where an ACK is queued while the loop is between retry sleeps, plus a lifecycle/ownership test that sends and receives only through the registered endpoint and handles loop shutdown cleanly.

### Missing Items
- A stable EventLoop endpoint name and chosen mailbox capacity/backpressure strategy for ACK frames.
- The mapping from `logIngestAckTimeoutMicros`/`logIngestRetryBackoffMicros` to EventLoop `recv` timeouts and retry sleeps.
- A statement that LogIngest protocol/frame ordering remains unchanged and that all LogBatch sends use `Zmqx.EventLoop.sends`, not the raw DEALER.

### Suggestions
- Prefer mailbox delivery unless there is a strong reason for callbacks: it keeps ACK decoding/state mutation in the existing logging loop instead of running application logic on the EventLoop worker thread.
