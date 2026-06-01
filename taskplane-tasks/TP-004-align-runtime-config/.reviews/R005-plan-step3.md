## Plan Review: Step 3: Testing & Verification

### Verdict: REVISE

### Summary
The build coverage in the Step 3 plan matches the prompt, and static address inspection is the right lightweight verification for this wiring task. However, the plan does not explicitly verify the explicit JSON config path/sample config files, which is part of the task mission and was called out as a remaining test gap in the Step 2 code review.

### Issues Found
1. **[Severity: important]** — The plan can pass both Cabal builds while still shipping malformed or mismatched sample JSON configs, because `cabal build` does not parse `applications/TaskSchedule/config/{broker,worker,client}.json`. Add a Step 3 verification outcome that either loads those files with `readBrokerConfig`, `readWorkerConfig`, and `readClientConfig` or performs an equivalent static inspection proving the explicit-config path uses the documented addresses and shapes.

### Missing Items
- Verification that explicit config files are usable, not just that built-in defaults compile and addresses are visually consistent.

### Suggestions
- Record the exact build commands and the address/config inspection result in `STATUS.md` so Step 4 documentation can cite the final verified defaults.
