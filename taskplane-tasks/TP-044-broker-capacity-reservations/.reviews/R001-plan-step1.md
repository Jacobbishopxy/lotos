## Plan Review: Step 1: Design reservation model

### Verdict: REVISE

### Summary
The submitted STATUS.md only repeats the Step 1 checklist and does not include the actual design decisions required by this checkpoint. Because this task changes broker scheduling/admission behavior, the implementation needs a concrete reservation model before coding: where state lives, how scheduler snapshots are adjusted without changing `LoadBalancerAlgo`, and exactly which events create/release reservations.

### Issues Found
1. **[Severity: important]** — No reservation-state location is selected. Step 1 explicitly requires deciding whether reservations live in the worker task map, a new broker map, or adjusted worker snapshots passed to `LoadBalancerAlgo`; the current plan records none of those decisions. Fix: document the chosen model and why it preserves scheduler extension semantics.
2. **[Severity: important]** — Reservation lifecycle is undefined. The plan must state when reservations are created on dispatch and released on worker heartbeat/status, task status (`TaskProcessing`, success, failure), and stale-worker recovery; otherwise Step 2 can easily leak capacity or double-count in-flight work. Fix: add a lifecycle table or equivalent event-by-event rules.
3. **[Severity: important]** — Public API compatibility strategy is missing. The mission requires preserving `LoadBalancerAlgo` semantics unless a documented extension is necessary, but the current plan does not say whether scheduler inputs remain unchanged or are transformed into reservation-adjusted snapshots. Fix: explicitly state that the public scheduler API is preserved, or document the extension and migration impact.

### Missing Items
- A concrete design artifact for Step 1 in STATUS.md Notes or another referenced file.
- Edge-case handling for same scheduling pass vs repeated passes before the next heartbeat.
- Stale-worker/retry interaction: recovered tasks should release/clear any reservation for the stale worker before being requeued.

### Suggestions
- Prefer a broker-owned reservation overlay applied before calling `scheduleTasks`; this likely keeps existing `LoadBalancerAlgo` implementations source-compatible while preventing over-assignment between heartbeats.
