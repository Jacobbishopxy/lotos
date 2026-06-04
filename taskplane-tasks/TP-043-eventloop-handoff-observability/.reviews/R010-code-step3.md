## Code Review: Step 3: Add regression coverage

### Verdict: REVISE

### Summary
The added tests compile and the two affected Cabal suites pass, but Step 3 still misses the explicit R006 current-depth interleaving regression that was required by the approved revised plan. Static quality checks were skipped because `.pi/taskplane-config.json` declares no typecheck/lint/format-check commands and there is no `package.json` fallback.

### Issues Found
1. **[lotos/test/ZmqWorkerFrames.hs:367] [important]** — The new stats-aware queue test is purely sequential: it enqueues two tasks, reads metrics, then drains both tasks in a single STM transaction. This covers basic high-water/current-depth accounting, but it would not catch the R006 bug where queue mutation and stats mutation were split across transactions and a producer/consumer interleaving left `hqsCurrentDepth` drifted. Add a regression that exercises concurrent or otherwise forced enqueue/dequeue interleaving against the production stats-aware enqueue/drain path (or a deterministic helper path that fails if queue and stats updates are not linearized), then assert final actual queue contents, `currentDepth`, totals, and high-water.

### Pattern Violations
- None found.

### Test Gaps
- The Step 3 STATUS checkbox at `STATUS.md:49` says the explicit current-depth linearizability/interleaving regression was added, but the diff only adds sequential coverage. This should remain unchecked until an interleaving/drift regression exists.

### Suggestions
- Targeted verification run: `cabal test lotos:test:test-zmq-worker-frames lotos:test:test-zmq-log-ingest` passed.
