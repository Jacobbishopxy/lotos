## Code Review: Step 2: Cleanup obsolete logging coupling

### Verdict: REVISE

### Summary
The `/info` snapshot itself is now scheduler-only and the diagram update is in scope. No configured typecheck/lint/format-check commands were present in `.pi/taskplane-config.json` and there is no `package.json`; supplemental `git diff --check` and `cabal build lotos` both passed. However, the obsolete InfoStorage/logging-address coupling still gates the LogIngest ROUTER, leaving a real configuration path where `/logs/*` is served but never populated.

### Issues Found
1. **[lotos/src/Lotos/Zmq/LBS.hs:93] [important]** — `runLBS` still skips `runLogIngest` when `logIngestAddr == infoStorage.loggingAddr` via `logIngestRouterEnabled`, even though Step 2 removed the InfoStorage SUB socket that previously caused that bind collision. With such a config, the worker logging DEALER connects to `workerLogging.logIngestAddr`, but the broker never binds a ROUTER, so `/logs/recent`, `/logs/worker/*`, and `/logs/stats` remain empty and the worker log loop retries forever. Fix: now that InfoStorage no longer consumes `loggingAddr`, start `runLogIngest` unconditionally (or change the guard to only cover actual active socket conflicts), remove/update the stale warning, and update `lotos/test/ZmqLogIngest.hs` so same-address configs are not expected to disable LogIngest.

### Pattern Violations
- The remaining `logIngestRouterEnabled` path preserves the legacy InfoStorage logging coupling that this cleanup step is meant to remove.

### Test Gaps
- `lotos/test/ZmqLogIngest.hs` still encodes the old expectation that an InfoStorage/LogIngest address collision disables the ROUTER; it should be revised or removed with the guard change.

### Suggestions
- After fixing the guard, refresh the nearby comments in `Lotos.Zmq.Config` that still describe `InfoStorageConfig.loggingAddr` as a SUB endpoint, so later documentation cleanup does not inherit stale code comments.
