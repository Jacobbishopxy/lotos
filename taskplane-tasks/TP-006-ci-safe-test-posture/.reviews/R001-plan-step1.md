## Plan Review: Step 1: Define safe test posture

### Verdict: APPROVE

### Summary
The proposed posture correctly inventories the current `lotos` Cabal test suites and distinguishes the single assertion-based regression suite from demo/long-running/server suites. The docs-only decision is appropriate for this task: it avoids hiding CI-hostile behavior while still giving developers safe quick, build-only, and intentional MVP smoke commands.

### Issues Found
None.

### Missing Items
None.

### Suggestions
- When applying the docs, make the smoke status explicit: `scripts/task-schedule-smoke.sh` is the bounded MVP command, but current TP-005 evidence exits as a hard failure before client submission due the worker-status parsing blocker; exit `2` only applies after worker marker proof exists and the remaining issue is client ACK.
- A compact README table for "safe default", "compile all tests", "intentional smoke", and "avoid as default" would make the posture easy to scan.
