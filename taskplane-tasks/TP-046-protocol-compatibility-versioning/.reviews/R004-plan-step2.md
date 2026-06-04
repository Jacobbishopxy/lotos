## Plan Review: Step 2: Harden tests/docs

### Verdict: APPROVE

### Summary
The Step 2 plan is aligned with the approved Step 1 policy: it protects the `WorkerState.taskCapacity` append-only change with both current-shape and old-frame decoding tests, adds the required mdBook protocol-compatibility chapter, and updates the README invariant summary. It also carries forward frame-order coverage expectations for other positional payloads without over-prescribing implementation details.

### Issues Found
None.

### Missing Items
None.

### Suggestions
- Since `docs/task-schedule-mvp.md` already mentions `WorkerState.taskCapacity`, explicitly check whether it needs a short compatibility-policy cross-reference while doing the documentation pass.
- Consider turning the Step 1 payload inventory into a table in the mdBook chapter so fallback status and frame-order coverage are easy to audit later.
