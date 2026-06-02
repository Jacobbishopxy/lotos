## Plan Review: Step 1: Define durability/retention contract

### Verdict: APPROVE

### Summary
The Step 1 contract in STATUS.md covers the required restart recovery, retention/compaction, socket HWM, and targeted test outcomes. The checkpoint-based compaction approach appropriately preserves restart idempotency when historical journal events are discarded, and the HWM plan matches the available `zmqx` socket option surface.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- Make the final implementation/docs explicit about non-positive `logIngestRetentionBytes` semantics and which `/logs/stats` fields make compaction/truncation visible to operators.
- If practical, include a small HWM startup/config compatibility assertion using a low configured HWM, even if the socket option itself is not easily introspected.
