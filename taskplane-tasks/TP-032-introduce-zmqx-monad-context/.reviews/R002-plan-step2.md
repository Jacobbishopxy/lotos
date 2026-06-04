## Plan Review: Step 2: Add explicit context to the app environment

### Verdict: APPROVE

### Summary
The Step 2 plan matches the task outcomes: extend the application environment with both logger and `Zmqx.Context`, provide the `MonadZmqx LotosApp` bridge, and ensure forked `LotosApp` actions keep the captured environment. Step 1's recorded runner decision covers the main compatibility risk, so this step should set up the explicit-context foundation without changing multipart protocol behavior.

### Issues Found
None.

### Missing Items
None.

### Suggestions
- While implementing, update the current `ask :: LoggerEnv`/`Logger.runApp` capture path in `Lotos.Zmq.LBW.LogTransport` to capture the full `LotosEnv` (or use the planned captured-env runner), so EventLoop callbacks do not accidentally create a fresh compatibility context.
- Keep the old `runApp` compatibility path separate from the env/context runner used by `forkApp`; `forkApp` should run the captured environment directly rather than re-entering a wrapper that can allocate a new ZMQ context.
