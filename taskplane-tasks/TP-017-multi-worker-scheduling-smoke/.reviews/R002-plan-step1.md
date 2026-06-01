## Plan Review: Step 1: Design multi-worker smoke

### Verdict: APPROVE

### Summary
The revised plan addresses the R001 blockers by adding unique per-run client configs/IDs for concurrent submissions and defining race controls plus a deterministic per-worker execution proof. The separate-helper approach, generated worker configs, bounded batching/timeouts, explicit cleanup, and current-run evidence criteria are sufficient for Step 1 and should support a reliable implementation.

### Issues Found
None.

### Missing Items
None.

### Suggestions
- When implementing Step 2, make the `/info.workerLoggingsMap` assertions explicitly per worker if practical, in addition to the worker-specific stdio-log proof, so the smoke validates both execution and HTTP observability for each worker.
- Preserve the exact evidence paths for ACKs, markers, worker stats, worker logs, `/info`, garbage snapshots, and cleanup results in the script output to simplify the code-review checkpoint.
