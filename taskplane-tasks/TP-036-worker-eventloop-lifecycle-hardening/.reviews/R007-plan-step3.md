## Plan Review: Step 3: Add regression coverage

### Verdict: REVISE

### Summary
The Step 3 plan covers the broad regression areas from the prompt: backend/log stopped-loop behavior, log drop visibility, and forked-action teardown. However, it does not explicitly carry forward the R005/R006 regression for the actual task-status callback path after backend transport stop, which is the path that previously blocked Step 2 and is not proven by only testing low-level EventLoop sends.

### Issues Found
1. **[Severity: important]** — `STATUS.md:50` and the test matrix at `STATUS.md:130` plan backend stopped-loop coverage around `sendWorkerBackendDealerFrames`/status-forward helpers, but R006 specifically identified the missing regression as invoking `taSendTaskStatus`/`sendTaskStatus` after the backend transport is marked stopped and asserting it returns promptly with failed-delivery logging (`.reviews/R006-code-step2.md:15`). Add that outcome to the Step 3 plan so the nonblocking STM handoff/`workerBackendRunning` guard is covered, not just the lower-level EventLoop stopped-send helper.

### Missing Items
- Explicit coverage that task execution/status callbacks do not hang or silently succeed after backend transport has stopped.

### Suggestions
- The existing logging stopped-loop, log drop-accounting, and forked teardown coverage intents are appropriate; keep those tests bounded with timeouts so lifecycle regressions fail fast.
