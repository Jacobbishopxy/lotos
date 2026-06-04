## Plan Review: Step 2: Implement EventLoop-backed ingestion

### Verdict: APPROVE

### Summary
The Step 2 plan is adequately grounded in the approved Step 1 design: it covers moving the ROUTER to explicit-context EventLoop ownership, handing received frames off to the ingestion loop, preserving existing dedupe/journal/retention behavior, and sending ACKs through the EventLoop endpoint. The prior R001/R002 concerns about avoiding built-in mailbox drops and keeping callback work lightweight are recorded in STATUS.md and should carry directly into this implementation step.

### Issues Found
None.

### Missing Items
- None blocking.

### Suggestions
- Carry forward the R002 implementation caution explicitly: keep the `withEventLoopIn` bracket alive for the full ingestion-loop lifetime, rather than forking inside the bracket and returning immediately.
- When adding dispatch/decode rejection accounting, keep those broker-side counters/log messages distinct from journal replay malformed-line accounting so `/logs/stats` remains interpretable.
