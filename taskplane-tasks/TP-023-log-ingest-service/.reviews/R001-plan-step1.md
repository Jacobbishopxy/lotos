## Plan Review: Step 1: Design ingestion/storage boundary

### Verdict: APPROVE

### Summary
The Step 1 draft covers the required boundary decisions: a narrow `LogIngest` state/service API, bounded worker/task cache indexes, JSONL persistence before ACK, and separate `/logs/...` routes rather than expanding `/info`. The duplicate, hidden-gap, and explicit-drop accounting direction is sufficient to guide Step 2 implementation while preserving the legacy PUB/SUB path during the staged worker switch.

### Issues Found
- None blocking.

### Missing Items
- None.

### Suggestions
- Make the JSONL schema explicit in the implementation/docs (for example, one existing `LogEvent` JSON object per line, plus any intentional envelope fields such as batch id or ingest time if added).
- When skipping `runLogIngest` because `logIngestAddr` collides with the legacy InfoStorage `loggingAddr`, log that limitation clearly and document how to opt into a non-colliding endpoint for exercising the new ROUTER service.
- Clarify in code comments/tests whether deduplication and contiguous ACK watermarks are keyed strictly per worker, and reject/log events whose `LogEvent.workerId` does not match the enclosing `LogBatch.workerId`.
