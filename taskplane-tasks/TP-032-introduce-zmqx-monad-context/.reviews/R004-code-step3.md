## Code Review: Step 3: Adapt runners without changing socket behavior

### Verdict: REVISE

### Summary
The explicit `LotosEnv`/`MonadZmqx` runner migration mostly compiles and the updated app/test call sites use the new `runZmqApp` surface as intended. However, the worker log transport still starts its EventLoop through the global-context API, while `runZmqApp` now uses `Zmqx.withContext` without installing a global context; this breaks worker log delivery under the new runner. Declared static quality checks were not configured (`.pi/taskplane-config.json` has no matching commands and there is no `package.json`), but I ran targeted Cabal builds/tests for review evidence.

### Issues Found
1. **[lotos/src/Lotos/Zmq/LBW/LogTransport.hs:165] [important]** — `runWorkerLogEventLoop` still calls `Zmqx.EventLoop.withEventLoop`, which reads the active global ZMQ context. The new `runZmqApp` runner at `Lotos.Logger:80-83` creates an explicit context via `Zmqx.withContext` and does not populate `globalContextRef`, so the log EventLoop cannot start correctly and no log batch is sent. This is reproducible with `cabal test lotos:test:test-zmq-worker-log-transport`, which fails the delayed-ACK case with `delayed ACK router did not observe a worker LogBatch`. Fix: use the explicit app context for the EventLoop, e.g. capture `Logger.askZmqContext`/`lotosZmqContext appEnv` and call `Zmqx.EventLoop.withEventLoopIn context spec` before `Logger.runAppWithEnv appEnv ...`.

### Pattern Violations
- The worker log transport mixes explicit-context socket creation (`ZmqxM.open`) with the legacy global-context EventLoop runner (`withEventLoop`). After this step, app-owned sockets should stay on the captured `LotosEnv` context throughout their lifecycle.

### Test Gaps
- No additional gap beyond the failing existing regression: `cabal test lotos:test:test-zmq-worker-log-transport` currently exposes the broken EventLoop context handoff.

### Suggestions
- Review evidence: `cabal build lotos` passed; `cabal build TaskSchedule:exe:ts-server TaskSchedule:exe:ts-worker TaskSchedule:exe:ts-client` passed; `cabal test lotos:test:test-zmq-log-ingest` passed; `cabal test lotos:test:test-zmq-worker-log-transport` failed as described above.
