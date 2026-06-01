## Plan Review: Step 1: Design the client path

### Verdict: APPROVE

### Summary
The plan aligns with the TP-002 MVP contract for the client: JSON task path as the required input, optional client config path, default config behavior, no new dependencies, non-zero failures, and ACK-only success semantics. It is sufficient to guide implementation of `ts-client` without changing the documented CLI surface.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- Make the timeout validation rule explicit during implementation: `taskTimeout` should equal `taskProp.executeTimeoutSec`, matching `docs/task-schedule-mvp.md`.
- When wiring ACK timeout behavior, verify the units used by `mkClientService`/`Z_RcvTimeO` so the documented `reqTimeoutSec` seconds contract is preserved.
- Catch config/task parsing and ZMQ send/receive exceptions so users see the planned clear stderr message instead of a raw Haskell `error`.
