## Plan Review: Step 1: Design explicit EventLoop context access

### Verdict: REVISE

### Summary
The task requirements are clear, but the submitted Step 1 plan has not yet made the required design decision. It currently restates the prompt checkboxes without specifying how the EventLoop context will be obtained or how socket/context ownership will be enforced during the Step 2 implementation.

### Issues Found
1. **[Severity: important]** — `STATUS.md:28-30` still leaves the central Step 1 decision open (`askContext`, `LotosEnv`, or helper wrapper). Before implementation, record the chosen approach and the ownership rule: sockets opened via the monadic explicit context must be registered only with `withEventLoopIn` using that same context, with no active-global-context fallback.

### Missing Items
- A concrete design note for the forked worker log loop: how it captures/reuses the worker service context after `forkApp` so `ZmqxM.open` and `withEventLoopIn` share the same `Zmqx.Context`.
- A documentation target for the future-migration constraint (e.g. `taskplane-tasks/CONTEXT.md`) stating that EventLoop-registered sockets are worker-owned while the loop runs and must not be used directly outside `EventLoop.send/recv`.

### Suggestions
- Prefer using the existing `MonadZmqx`/`askZmqContext` path for context access; only add a helper wrapper if it removes duplication across multiple EventLoop migrations.
