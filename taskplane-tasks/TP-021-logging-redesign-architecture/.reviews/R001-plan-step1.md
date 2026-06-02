## Plan Review: Step 1: Document target logging architecture

### Verdict: APPROVE

### Summary
The Step 1 plan covers the required architecture deliverables: a dedicated `docs/logging-redesign.md`, a diagram update moving logging out of InfoStorage/PUB-SUB, and conditional updates to adopter-facing docs that still present the current logging path as durable guidance. This is appropriately scoped for a documentation-only architecture TP and preserves the stated boundary of not implementing later runtime protocol changes.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- In `docs/logging-redesign.md`, make the distinction between current behavior and target architecture explicit so readers do not assume the DEALER/ROUTER log channel already exists.
- While checking README/build-your-own-scheduler references, consider noting any stronger PUB/SUB/current-state language found in other docs (for example MVP/runtime docs) as follow-up debt if it remains outside this TP's file scope.
