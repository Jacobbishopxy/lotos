## Plan Review: Step 3: Convert send/receive/poll call sites consistently

### Verdict: APPROVE

### Summary
The Step 3 plan targets the right remaining direct runtime operations (`sends`/`receives`/`receivesFor`/`poll`/`pollFor`, plus simple `send`) and correctly limits scope by leaving EventLoop, socket options, and subscriptions unchanged. The post-conversion grep/documentation pass is important and should catch the remaining demo/test exceptions without expanding into TP-034.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- Preserve the current `zmqUnwrap`/`zmqThrow` wrapping around the monadic calls so error behavior stays identical while only the ZMQ surface changes.
- Treat pure poll-item builders such as `Zmqx.pollIn`/`pollInAlso` separately from blocking poll operations; keeping them qualified from `Zmqx` is not a direct global socket operation.
