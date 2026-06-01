## Plan Review: Step 2: Implement cleanup

### Verdict: APPROVE

### Summary
The Step 2 plan directly follows the approved wired-logging stance: it covers the server/worker 5557 endpoint alignment, worker-id topic framing, persisted info-storage buffers, smoke verification, and docs/config updates. The acceptance criteria are outcome-focused and address the main discovered failure modes, including the currently empty `workerLoggingsMap` and the need for current-run evidence.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- Preserve broker config compatibility where practical, or document the schema change clearly if `InfoStorageConfig` gains a required logging endpoint field.
- Make the smoke assertion poll `/SimpleServer/info` long enough for `infoFetchIntervalSec` and require both the expected worker key and current `RUN_ID`, so a correct transport is not failed by refresh timing and stale logs cannot pass.
