## Code Review: Step 2: Convert broker and worker service sockets

### Verdict: APPROVE

### Summary
The Step 2 changes are narrowly scoped and correctly convert the broker/worker service setup `bind`/`connect` sites to the `Zmqx.Monad` helper surface while leaving protocol send/receive/poll loops unchanged for Step 3. Existing `zmqUnwrap`/`zmqAppUnwrap` behavior is preserved, and a grep confirms no remaining direct `Zmqx.bind`/`Zmqx.connect` sites under `lotos/src/Lotos/Zmq`.

Quality checks: `.pi/taskplane-config.json` declares no typecheck/lint/format-check commands and there is no `package.json`; I additionally ran `cabal build lotos`, which completed successfully (`Up to date`).

### Issues Found
None.

### Pattern Violations
- None.

### Test Gaps
- None blocking for this setup-only step; send/receive/poll behavioral coverage remains appropriately deferred to Step 3/Step 4.

### Suggestions
- The stale inline comment in `LBS.SocketLayer` says `-- Fixed to use connect` next to a `bind`; consider cleaning it up later to avoid confusion.
