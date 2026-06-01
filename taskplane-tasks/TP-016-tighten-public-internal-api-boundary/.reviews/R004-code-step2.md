## Code Review: Step 2: Apply boundary cleanup

### Verdict: APPROVE

### Summary
The facade cleanup removes the retry-disposition/readiness helpers from `Lotos.Zmq` while preserving the intended protocol, config, client/server/worker, and utility exports. The updated worker-frame test imports the retry surface through the narrower `Lotos.Zmq.Internal.Retry` module, and the post-change tree builds with `cabal build all --enable-tests`; `cabal test lotos:test:test-zmq-worker-frames` also passes. No configured typecheck/lint/format commands were declared in `.pi/taskplane-config.json`, and no `package.json` fallback scripts exist.

### Issues Found
None.

### Pattern Violations
- None.

### Test Gaps
- None for this step; the touched retry-helper assertions remain covered by `test-zmq-worker-frames`, and the explicit facade export list was compile-checked across all packages/tests.

### Suggestions
- In the documentation/delivery step, remember to update `taskplane-tasks/CONTEXT.md` and any README public-module guidance that still points users at broader internal modules.
