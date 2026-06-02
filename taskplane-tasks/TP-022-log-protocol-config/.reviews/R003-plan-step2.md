## Plan Review: Step 2: Implement protocol/config and tests

### Verdict: APPROVE

### Summary
The Step 2 plan carries forward the approved compatibility boundary from Step 1: add the new structured log protocol/config surface while keeping the existing `WorkerLogging` PUB/SUB payload untouched. Its outcomes cover the required serialization/Aeson work, config knobs, public exports/comments, and bounded test coverage needed before later TPs switch transports.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- Include explicit regression tests for the exact `LogBatch`/`LogAck` multipart frame order and for the unchanged `WorkerLogging` `[taskUuid, loggingText]` frame shape.
- Add old-shape broker/worker JSON fixtures to prove the new logging config fields default correctly when omitted.
- Ensure the structured event model and tests cover sequence numbers plus visible dropped/gap metadata so the implementation cannot silently hide lost log lines.
