## Plan Review: Step 1: Map current runner/context usage

### Verdict: APPROVE

### Summary
The Step 1 plan targets the right discovery outcomes before changing the runner surface: complete inventory of current context runners/socket opens, public runner compatibility decisions, and tests/demos that rely on current global-context behavior. I spot-checked the repo and these are the relevant risk areas for TP-032, especially `Lotos.Logger`, `Lotos.Zmq.Util`, app entry points, and direct socket opens in broker/worker/client modules and frame/logging tests.

### Issues Found
None.

### Missing Items
None.

### Suggestions
- When executing the inventory, include the worker log transport/EventLoop path as a separate note because it opens a DEALER before handing it to `Zmqx.EventLoop`.
- Confirm the `Zmqx.Monad` API (`MonadZmqx`, `runZmqx`, `runZmqxT`, `open`) while deciding the runner shape so Step 2/3 do not need to revisit the public compatibility decision.
