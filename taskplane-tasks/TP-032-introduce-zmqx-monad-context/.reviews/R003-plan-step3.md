## Plan Review: Step 3: Adapt runners without changing socket behavior

### Verdict: APPROVE

### Summary
The Step 3 plan covers the necessary adaptation outcomes: make the explicit-context app runner the entry-point surface, retain compatibility wrappers, and update executable/test call sites that currently nest `runZmqContextIO` around `runApp`. This is the right next step after Step 2's `LotosEnv`/`MonadZmqx` work, and it should preserve socket behavior as long as raw direct-socket frame tests keep their existing context wrapper.

### Issues Found
None.

### Missing Items
None.

### Suggestions
- For `TaskScheduleServer`, keep the long-lived `forever` delay inside the new app/context runner; `runLBS` starts background threads and returns, so closing the explicit context immediately after `run lbsConfig` would break those forked socket loops.
- Distinguish app-level call sites from raw direct-socket tests: replace nested `runZmqContextIO $ runApp ...` for `LotosApp` services, but leave frame-only/direct ZMQ tests under `runZmqContextIO` unless they are intentionally migrated to `MonadZmqx` APIs.
- Consider re-exporting the new runner surface from `Lotos.Zmq` if it is intended as part of the public load-balancer facade, since the old context wrappers are already available there via `Lotos.Zmq.Util`.
