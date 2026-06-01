## Plan Review: Step 1: Plan ACK semantics and frame shape

### Verdict: APPROVE

### Summary
The Step 1 plan correctly identifies the current ROUTER/REQ envelope problem and the required reply shape: the server must decode `[clientRoutingId, "", task...]` and send `[clientRoutingId, "", ack]` so the REQ client receives exactly the ACK frame. It also keeps the ACK semantics scoped to broker acceptance/enqueue, not worker completion, and includes appropriate minimal code changes plus a focused frame regression and runtime verification path.

### Issues Found
- None.

### Missing Items
- None.

### Suggestions
- Because `RouterFrontendIn/Out` constructors are exported, prefer either preserving constructor compatibility where practical or documenting any intentional constructor-shape cleanup in the delivery notes so downstream users understand the protocol/API change.
