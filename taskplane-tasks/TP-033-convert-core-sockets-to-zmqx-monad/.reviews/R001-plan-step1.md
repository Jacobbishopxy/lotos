## Plan Review: Step 1: Convert low-risk socket creation sites

### Verdict: APPROVE

### Summary
The Step 1 plan matches the task goal: start with the isolated `LBC` client path, then convert low-risk frame/helper tests while deferring broker/worker runtime loops to later steps. The grouping keeps protocol-sensitive changes local and explicitly preserves existing unwrap/assertion behavior, which is appropriate for a low-risk first slice.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- When converting the raw frame tests, explicitly replace `runZmqContextIO` bodies with a `MonadZmqx` runner such as `ZmqxM.runZmqx Zmqx.defaultOptions` (or an existing app-context runner where already in `LotosApp`), since `ZmqxM.open` requires `MonadZmqx`; the existing `unwrap` helpers can otherwise remain compatible with `ZmqxM.connect`/`sends`/`receives*` results.
- Keep the Step 1 diff limited to `LBC` plus the named test helpers, and leave `ZmqXT`/demo-style direct calls for the later exception sweep unless they are needed for the targeted build.
