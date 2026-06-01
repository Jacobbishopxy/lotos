## Plan Review: Step 1: Design smoke approach

### Verdict: APPROVE

### Summary
The Step 1 plan now defines the concrete server, worker, and client command sequence; bounded readiness/verification probes; and safe cleanup strategy for spawned long-running processes. The prior R001/R002 blockers are addressed by explicit known-ACK classification, per-run marker/evidence guarding, and spawned process health checks during readiness.

### Issues Found
None.

### Missing Items
None.

### Suggestions
- When implementing, treat the newer per-run marker/evidence guard as authoritative and avoid using the earlier shared `.tmp/task-schedule-demo.out` example as pass evidence.
- If the script uses non-portable helpers such as `timeout` or `setsid`, include a small fallback or clear prerequisite message.
