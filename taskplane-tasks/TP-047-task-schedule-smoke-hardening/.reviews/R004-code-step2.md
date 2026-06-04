## Code Review: Step 2: Harden deterministic runtime evidence

### Verdict: APPROVE

### Summary
The smoke script changes satisfy Step 2: both scripts now assert `/info.runtimeQueueStats`, keep `/logs/stats` scoped to LogIngest accounting, and the multi-worker smoke generates configurable worker capacity plus checks reservation-safe in-flight assignment. The requested baseline hash was not present exactly, so I reviewed against the matching local baseline commit `d80f76e327711c708831b5eaec1c654619c84a30`; no configured static quality commands exist in `.pi/taskplane-config.json` and there is no `package.json`, so I ran supplemental shell checks (`bash -n ...` and `git diff --check`), both passing.

### Issues Found
None.

### Pattern Violations
None.

### Test Gaps
None blocking. I inspected the recorded Step 2 smoke evidence under `.tmp/...123025Z-1235128` and `.tmp/...123233Z-1237722`; I did not rerun the full smoke scripts during review.

### Suggestions
- Consider centralizing the duplicated `runtimeQueueStats` grep helper between the two scripts in a future cleanup pass if these smoke scripts continue to grow.
