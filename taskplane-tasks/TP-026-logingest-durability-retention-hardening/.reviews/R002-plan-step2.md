## Plan Review: Step 2: Implement restart recovery and retention enforcement

### Verdict: APPROVE

### Summary
The Step 2 plan carries forward the approved Step 1 contract and covers the required outcomes: journal reload, malformed-line tolerance, bounded compaction with idempotency-preserving checkpoints, socket HWM application, and API/at-least-once preservation. The targeted implementation path is consistent with the existing LogIngest state model and worker DEALER/ROUTER transport.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- During compaction, prefer writing a replacement journal/checkpoint to a temporary file and atomically renaming it into place so a broker crash cannot corrupt the only journal copy.
- Keep recovery tolerant of legacy one-`LogEvent`-per-line journals and avoid re-rejecting already-durable events merely because current size-limit config was tightened after they were written.
- Make non-positive `logIngestRetentionBytes` semantics explicit in code/docs, even if the implementation treats it as “no compaction” or “compact opportunistically only when safe.”
