## Code Review: Step 2: Implement `ts-client`

### Verdict: REVISE

### Summary
The CLI parsing, JSON task validation, default/config loading, and ACK output are largely wired as intended. Static quality checks were not declared in `.pi` or `package.json`; `cabal build TaskSchedule:exe:ts-client` and `git diff --check` passed. However, the implementation does not yet satisfy the contract that no ACK within `reqTimeoutSec` exits non-zero with a clear error.

### Issues Found
1. **[applications/TaskSchedule/app/TaskScheduleClient.hs:63] [important]** — `submitClientTask` calls `sendTaskRequest` without any overall timeout, and the underlying `Zmqx.Req.sends` path can block before the receive timeout is reached when the broker is absent/unreachable. I verified `cabal run TaskSchedule:exe:ts-client -- /tmp/task-demo-review.json` with no server running hung until the review command timed out after 60s, instead of exiting non-zero within the default 5 seconds. Fix: enforce the `reqTimeoutSec` contract around the full submit operation (send + receive), or use a timeout-aware/non-blocking send path, and map timeout expiry to the existing clear “no ACK received” failure.
2. **[applications/TaskSchedule/app/TaskScheduleClient.hs:67] [important]** — The client passes `reqTimeoutSec` straight into `mkClientService`, but `mkClientService` currently sets `Z_RcvTimeO` directly (`lotos/src/Lotos/Zmq/LBC.hs:36`), and ZMQ receive timeouts are milliseconds. A config value of `5` therefore means 5ms, not the contract’s 5 seconds, causing spurious ACK failures even when a broker responds slightly later. Fix: convert the external seconds value to milliseconds before configuring the ZMQ socket (preferably in the client-service layer or via a clearly named helper) while preserving the JSON/config field as seconds.

### Pattern Violations
- None.

### Test Gaps
- Add/record coverage for the no-broker/no-ACK timeout path so it cannot regress into an indefinite hang.
- Add argument/task-validation checks for bad arity, non-null `taskID`, negative timeouts, and mismatched `taskTimeout`/`executeTimeoutSec`.

### Suggestions
- Consider reusing the existing `readClientConfig` helper instead of duplicating Aeson file decoding in the executable.
