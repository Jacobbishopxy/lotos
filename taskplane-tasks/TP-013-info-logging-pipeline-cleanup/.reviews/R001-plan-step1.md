## Plan Review: Step 1: Decide logging product stance

### Verdict: APPROVE

### Summary
The Step 1 notes satisfy the checkpoint: they accurately trace the current worker PUB path, the mismatched info-storage SUB endpoint/frame expectations, and the observed empty `workerLoggingsMap`. Choosing to wire the existing 5557 logging path is consistent with the prompt, and the acceptance criteria cover endpoint alignment, worker-id topic framing, smoke verification, and documentation cleanup.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- When adding the server-side logging endpoint to `InfoStorageConfig`, consider preserving old broker JSON compatibility with a default `5557` value or explicitly documenting the config schema migration.
- Make the smoke assertion poll `/SimpleServer/info` until `infoFetchIntervalSec` has had a chance to refresh; otherwise a correct log transport could still look empty in an immediate final snapshot.
