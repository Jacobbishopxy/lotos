## Plan Review: Step 1: Plan lifecycle/failure coverage

### Verdict: APPROVE

### Summary
The Step 1 plan covers the required lifecycle semantics: success/failure/timeout status mapping, retry decrement and requeue behavior, exhausted retry garbage handling, and the current no-delay retry-interval limitation. The selected strategy is appropriately bounded, favoring HUnit-style unit/component tests and keeping live failure smoke optional unless unit coverage exposes an integration-only gap.

### Issues Found
None.

### Missing Items
None.

### Suggestions
- When implementing the TaskSchedule worker tests, make sure they are wired into a Cabal test target or otherwise into an existing bounded regression target so they run under the Step 3 gates; the current plan names the coverage but not the harness.
- Consider including the retry boundary cases explicitly in the bounded retry/garbage tests: retry count `1` should requeue with `0`, while retry count `0` should go straight to the garbage bin.
