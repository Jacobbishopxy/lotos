## Code Review: Step 4: Testing & Verification

### Verdict: APPROVE

### Summary
The lifecycle changes remain consistent with the approved Step 3 semantics: backend status sends are routed through the shutdown-aware STM handoff, stopped backend/log EventLoops terminate their loops instead of retrying indefinitely, and forked `LotosApp` children are waited on during context teardown. No configured static typecheck/lint/format commands are available in `.pi/taskplane-config.json` and there is no `package.json`; I verified the tree with `git diff --check`, `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-worker-wake lotos:test:test-zmq-worker-log-transport`, and `cabal build all --enable-tests`, all of which passed.

### Issues Found
None.

### Pattern Violations
- None blocking.

### Test Gaps
- None blocking for the lifecycle/failure semantics under review. The Step 4 smoke-script checkbox should still be completed or explicitly waived by the worker because the worker runtime loops changed materially.

### Suggestions
- Consider a follow-up to make `forkApp` registration fully async-exception-safe (mask around fork/register or use an `Async`-style registry), as noted in R011.
