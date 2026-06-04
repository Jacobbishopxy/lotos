## Plan Review: Step 2: Convert broker and worker service sockets

### Verdict: APPROVE

### Summary
The Step 2 plan is appropriately scoped: it focuses on broker/worker service setup `bind`/`connect` calls in the requested modules while preserving existing `zmqUnwrap` error behavior and explicitly deferring `poll`/`sends`/`receives` and EventLoop migration to later steps. Current target-module socket opens are already on `ZmqxM.open`, so converting the remaining open-adjacent setup calls should satisfy this step without disturbing protocol handlers.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- After implementation, run a narrow grep for `Zmqx.bind`/`Zmqx.connect` in `LBS.*`, `LBW`, and `LBW.LogTransport` to catch any missed setup-site conversions before moving to Step 3.
