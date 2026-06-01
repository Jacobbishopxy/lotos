## Plan Review: Step 1: Plan frame coverage matrix

### Verdict: APPROVE

### Summary
The coverage matrix in `STATUS.md` satisfies the Step 1 requirements: it lists the required client/frontend and worker/backend frame directions, maps each to existing or planned bounded tests, and explicitly avoids production helper extraction. The planned additions focus on the real gaps—worker task-status frames, retry/failure status payloads, and backend ROUTER-to-DEALER task delivery—without broad refactoring.

### Issues Found
None.

### Missing Items
None.

### Suggestions
- When implementing deterministic task IDs or ACKs, avoid adding direct `uuid`/`time` test dependencies unless necessary; using existing `fillTaskID'`, `unsafeGetTaskID`, and `newAck` can keep Cabal metadata unchanged.
