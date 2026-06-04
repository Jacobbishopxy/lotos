## Plan Review: Step 3: Add regression coverage

### Verdict: REVISE

### Summary
The Step 3 plan covers the main prompt-level outcomes: queue metric updates, protocol/scheduling invariants, and keeping LogIngest drop accounting separate from no-drop handoff metrics. However, it does not explicitly carry forward the known R006 regression: `currentDepth` drift under enqueue/dequeue interleavings when queue mutations and metric updates are not linearized. Because this task is specifically adding regression coverage after that fix, the plan should name at least one interleaving/concurrency/current-depth regression so it is not missed.

### Issues Found
1. **[Severity: important]** — Missing explicit regression for stats depth linearizability under producer/consumer interleavings. R006 identified that separate queue and stats updates could leave `hqsCurrentDepth` permanently non-zero after a concurrent dequeue; Step 2 fixed that by moving updates into the same STM transactions. Add a Step 3 test outcome that exercises an enqueue/dequeue interleaving (or direct STM helper path) and asserts final `currentDepth`, totals, and high-water remain consistent with the actual queue.

### Missing Items
- Add coverage intent for `currentDepth` as well as high-water metrics, including the R006 interleaving/drift case.

### Suggestions
- Consider also asserting warning-threshold behavior (`takeHandoffQueueWarning` only emits on threshold/new high-water and throttles) as a small unit test, though the linearizability regression is the blocking gap.
