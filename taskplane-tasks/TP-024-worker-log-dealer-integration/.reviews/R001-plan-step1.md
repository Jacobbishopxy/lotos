## Plan Review: Step 1: Plan worker-side reliability semantics

### Verdict: REVISE

### Summary
The plan captures the right high-level shape: a separate logging DEALER, bounded worker buffering, visible gap events, and non-blocking task execution. However, Step 1 explicitly asks for retry/ACK timeout semantics, and the current draft leaves the timeout/backoff/idle-flush behavior too ambiguous to guide a safe implementation. It also needs to pin sequence-number scope to the broker's per-worker accepted-through model before coding.

### Issues Found
1. **[Severity: important]** — `STATUS.md:71` says batches drain on record/byte limits “plus retry timeout” and retry until ACK, but it does not define the actual ACK wait/backoff/flush semantics. This leaves room for either low-volume logs to sit indefinitely below max batch thresholds or for a tight retry/blocking receive loop when the broker is unavailable. Fix: state that the logging thread flushes partial batches on an idle/short timeout, waits for ACKs using bounded polling, retries with bounded backoff, and handles `LogAck` rejection/partial acceptance without retrying the same invalid batch forever.
2. **[Severity: important]** — The plan does not explicitly define `logEventSeq` scope, even though LogIngest tracks `acceptedThrough` by worker (`acceptedThroughByWorker`) and gap/drop accounting depends on contiguous worker sequence ranges. If the worker implementation chooses per-task counters under concurrent tasks, the broker will see cross-task duplicates/gaps incorrectly. Fix: add to the plan that each worker owns one monotonic sequence counter for all LogEvents, including synthetic gap events, and that dropped ranges cover the discarded worker-sequence span without reusing sequence numbers.

### Missing Items
- A concrete statement of the retry/ACK timeout source/default (new config field or fixed internal constant) and how it relates to batch flush timing.
- Worker-wide sequence/gap-marker semantics aligned with the existing broker watermark and `/logs/stats` counters.

### Suggestions
- Consider noting that any currently queued unsent high-priority result/error events should be preferred over verbose logs when building the next batch, not just when dropping from the buffer.
