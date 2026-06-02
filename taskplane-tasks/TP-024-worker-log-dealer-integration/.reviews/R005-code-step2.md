## Code Review: Step 2: Implement worker transport switch

### Verdict: REVISE

### Summary
The worker/broker transport switch mostly follows the approved Step 2 plan: a bounded worker buffer, separate LogIngest DEALER loop, config split to 5558, compatibility backfill, and targeted ACK/drop tests are present. No declared typecheck/lint/format commands were configured (`.pi/taskplane-config.json` has an empty command map and there is no `package.json`); I ran `cabal test lotos:test:test-zmq-worker-log-transport lotos:test:test-zmq-log-protocol-config TaskSchedule:test:test-worker-lifecycle` and `cabal build TaskSchedule:exe:ts-server TaskSchedule:exe:ts-worker`, both of which passed. However, stderr output is still encoded as stdout/info LogEvents, so the stated stdout/stderr stream-preservation requirement is not met.

### Issues Found
1. **[applications/TaskSchedule/src/Worker.hs:47] [important]** — All live command output is enqueued as `LogStdout`/`LogInfo`, even though `ConcExecutor` still prefixes stderr lines as `"STDERR: ..."` (`lotos/src/Lotos/Proc/ConcExecutor.hs:108,140`). This loses the new structured stderr stream/level semantics required by Step 2. Fix by mapping the existing `STDOUT:`/`STDERR:` prefixes (or changing `ConcExecutor` to pass a structured stream) so stderr lines use `LogStderr` with an appropriate warning/error level while stdout remains `LogStdout`/`LogInfo`; add a regression test that a command writing to stderr produces `LogStderr`.

### Pattern Violations
- None found.

### Test Gaps
- The new worker transport tests cover ACK/retry/drop state, but no test exercises TaskSchedule stdout-vs-stderr mapping through `processTasks`, which allowed the stderr stream regression above.

### Suggestions
- Consider applying `logIngestSocketHWM` to the ROUTER/DEALER sockets in a follow-up so the configured socket bound is not just documented.
