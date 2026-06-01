## Plan Review: Step 1: Audit public exports

### Verdict: APPROVE

### Summary
The audit captures the current `Lotos.Zmq` facade surface and correctly separates intended extension/config/protocol exports from the retry-disposition helpers that are only needed by internals/tests. The proposed narrow `Lotos.Zmq.Internal.Retry` access path plus README/CONTEXT follow-up is conservative and satisfies the task's public-facade tightening goal.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- During implementation, make sure the planned internal retry module is actually importable by the test suite without re-exporting those helpers from `Lotos.Zmq`.
- Because `Lotos.Zmq` currently re-exports `module Lotos.Zmq.Adt` wholesale, the cleanup will need an explicit/non-wholesale facade export shape (or equivalent) so the retry helpers do not leak transitively.
