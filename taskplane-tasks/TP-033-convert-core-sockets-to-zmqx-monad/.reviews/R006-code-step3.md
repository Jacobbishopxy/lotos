## Code Review: Step 3: Convert send/receive/poll call sites consistently

### Verdict: APPROVE

### Summary
The send/receive/poll conversions are consistent with the approved Step 3 plan and preserve existing `zmqUnwrap`/`zmqThrow` handling in the core broker and worker loops. I found no remaining direct `Zmqx.sends`/`send`/`receives`/`receivesFor`/`poll`/`pollFor` socket operations in `lotos/src`, `lotos/test`, or `applications`; remaining `Zmqx.*` uses are socket options, context helpers, types, or intentional EventLoop calls. No declared typecheck/lint/format commands are configured in `.pi/taskplane-config.json` and no `package.json` scripts exist; as an additional compile sanity check, `cabal build lotos` passed (`Up to date`).

### Issues Found
None.

### Pattern Violations
- None found.

### Test Gaps
- None blocking for this step. The broader protocol/frame and full build verification remains scheduled for Step 4.

### Suggestions
- When documenting the final exception list in Step 5, include the still-direct categories visible in grep: socket options/subscriptions, `Zmqx.EventLoop.*`, context setup, and type/name constructors.
