## Code Review: Step 1: Design explicit EventLoop context access

### Verdict: APPROVE

### Summary
Step 1 only changes task/design documentation, and the recorded decision matches the approved plan: use `ZmqxM.askContext` for the EventLoop context, capture `LotosEnv` only to rerun `LotosApp`, and keep EventLoop-registered sockets owned by the loop. Quality checks were not run because `.pi/taskplane-config.json` declares no typecheck/lint/format-check commands and there is no `package.json` fallback.

### Issues Found
None.

### Pattern Violations
- None.

### Test Gaps
- None for this design/documentation-only step; implementation verification remains scheduled in Step 3.

### Suggestions
- When Step 2 updates `LogTransport`, keep the `askContext` call adjacent to `withEventLoopIn` so the same-context invariant remains auditable.
