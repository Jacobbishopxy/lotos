## Plan Review: Step 2: Cleanup obsolete logging coupling

### Verdict: APPROVE

### Summary
The plan targets the right Step 2 outcomes: remove the legacy `/info.workerLoggingsMap` coupling, keep `/info` focused on scheduler state, preserve the `/logs/*` LogIngest query surface, and refresh the architecture diagram. This is consistent with the PROMPT's cleanup goal and Step 1's move away from `/info.workerLoggingsMap` in smoke coverage.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- While removing the InfoStorage SUB/ring-buffer bridge, make sure `infoFetchIntervalSec` still controls the scheduler snapshot loop so the replacement does not busy-loop or stop refreshing `/info`.
- Check the obsolete LogIngest/InfoStorage address-collision guard and related comments (`logIngestRouterEnabled` / `runLBS`) so removing the legacy SUB path does not leave a configuration path where LogIngest is skipped.
