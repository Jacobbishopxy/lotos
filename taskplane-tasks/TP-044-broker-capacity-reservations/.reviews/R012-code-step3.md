## Code Review: Step 3: Add tests

### Verdict: APPROVE

### Summary
The latest change routes TaskProcessor stale-worker cleanup through the shared `releaseWorkerReservations` lifecycle helper, matching the helper exercised by the capacity reservation regression suite. No configured static quality commands were available in `.pi/taskplane-config.json` or `package.json`; I ran the targeted reservation test suite and it passed.

### Issues Found
None.

### Pattern Violations
None.

### Test Gaps
None blocking. Existing `test-zmq-capacity-reservations` coverage now includes stale-worker helper release behavior, and TaskProcessor calls that helper at `lotos/src/Lotos/Zmq/LBS/TaskProcessor.hs:186`.

### Suggestions
- Verification run: `cabal test lotos:test:test-zmq-capacity-reservations` passed (5 cases).
