## Plan Review: Step 1: Design LogIngest EventLoop ownership

### Verdict: REVISE

### Summary
The plan preserves the key protocol and durability intent, but it relies on `Zmqx.EventLoop.Mailbox` while also promising observable mailbox-overload accounting. The current EventLoop mailbox API silently drops full-mailbox deliveries, so the plan needs a concrete dispatch mechanism before implementation can satisfy the task's backpressure/accounting requirements.

### Issues Found
1. **[Severity: important]** — Built-in EventLoop `Mailbox` delivery cannot provide the planned overload accounting. `Zmqx.EventLoop` documents full mailboxes as dropping the newest message (`EventLoop.hs:126-127`), and the implementation discards the `tryWriteMailbox` result (`EventLoop.hs:472-480`), so LogIngest cannot log/count mailbox-dispatch misses if it uses `Mailbox` as drafted. Revise the design to make overload observable, e.g. use a lightweight `Callback` that `tryWriteTBQueue`s into a LogIngest-owned bounded queue and increments/logs an overload counter on `False`, or explicitly include an EventLoop API change plus tests that exposes mailbox drop accounting.

### Missing Items
- A concrete accounting path for mailbox-full/drop cases that is implementable with the current EventLoop API or explicitly expands scope to change that API.

### Suggestions
- Prefer deriving the queue/mailbox capacity from `logIngestSocketHWM` or a dedicated LogIngest config value; `logIngestBatchMaxRecords` is a per-batch record limit, not a natural number of queued multipart batches.
