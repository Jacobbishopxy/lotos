## Plan Review: Step 2: Implement wake-on-enqueue and cleanup

### Verdict: APPROVE

### Summary
The Step 2 plan covers the required implementation outcomes: add a coalescing worker wake signal, signal it after successful task enqueue, replace the 10-second empty-queue sleep, and remove the broker hot-loop `putStrLn`. It also carries forward the Step 1 review fix by planning a dedicated `test-zmq-worker-wake` regression for promptness, coalescing, and worker counter transitions.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- When implementing the internal worker-runtime helper, keep the counter-transition assertions at deterministic single-cycle checkpoints; the full recursive `tasksExecLoop` may immediately consume the remaining queued task.
- Make the new helper/test import path and Cabal test-suite stanza part of the implementation so `test-zmq-worker-wake` is actually built by `cabal build all --enable-tests`.
