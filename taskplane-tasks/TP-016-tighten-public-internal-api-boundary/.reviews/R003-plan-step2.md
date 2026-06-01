## Plan Review: Step 2: Apply boundary cleanup

### Verdict: APPROVE

### Summary
The Step 2 plan follows the approved audit: remove retry-disposition helpers from the `Lotos.Zmq` facade, keep legitimate protocol/config/extension exports available, and update the bounded tests to use a narrow internal retry import. This should satisfy the task outcome without changing retry behavior or broadening the public facade unnecessarily.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- Ensure `Lotos.Zmq.Internal.Retry` is actually visible to the test suite via Cabal metadata without re-exporting those helpers from `Lotos.Zmq`.
- When replacing the wholesale `module Lotos.Zmq.Adt` facade export, double-check that ACK helpers, protocol wrappers, worker task-map helpers, triggers, and documented extension/config entry points remain exported.
