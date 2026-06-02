## Code Review: Step 2: Implement worker transport switch

### Verdict: APPROVE

### Summary
The R005 stderr-stream blocker has been addressed: TaskSchedule now maps `STDOUT:`/`STDERR:` prefixes to structured `LogStream`/`LogLevel` values and has a regression test for stderr. The Step 2 transport switch now covers the required separate worker LogIngest DEALER loop, bounded enqueue/drop/ACK state machine, split broker/worker logging defaults, and compatibility backfill. No declared typecheck/lint/format commands are configured (`.pi/taskplane-config.json` has an empty command map and there is no `package.json`); targeted Cabal verification passed.

### Issues Found
- None.

### Pattern Violations
- None found.

### Test Gaps
- No blocking gaps. The tests exercise the worker transport state machine and TaskSchedule stderr mapping; a future end-to-end ROUTER/DEALER smoke test would add confidence but is not required for this step because the plan explicitly allowed bounded fakes for slow ZMQ integration.

### Suggestions
- Consider preserving stream/level hints when backfilling legacy `/info.workerLoggingsMap` from reliable `LogEvent`s, since that legacy text-only view otherwise loses the old `STDOUT:`/`STDERR:` prefix distinction.
- Follow up on the already-noted hardening item to apply `logIngestSocketHWM` to the ROUTER/DEALER sockets.

Verification run:
- `cabal test lotos:test:test-zmq-worker-log-transport lotos:test:test-zmq-log-protocol-config TaskSchedule:test:test-worker-lifecycle` — passed.
- `cabal build TaskSchedule:exe:ts-server TaskSchedule:exe:ts-worker` — passed.
