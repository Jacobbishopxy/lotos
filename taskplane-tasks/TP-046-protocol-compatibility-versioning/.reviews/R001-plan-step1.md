## Plan Review: Step 1: Define compatibility policy

### Verdict: REVISE

### Summary
The proposed policy direction is sound: it treats positional multipart frames as a stable wire ABI, restricts compatible changes to append-only payload tails with decoder fallbacks, defers version tags deliberately, and defines break criteria. However, Step 1 also explicitly requires an inventory of current positional payloads and their fallback status, and the current plan note does not include or commit to that inventory.

### Issues Found
1. **[Severity: important]** — The Step 1 plan in `STATUS.md:65` covers the general compatibility policy and version-tag decision, but it misses the required outcome from `STATUS.md:26`: identifying all current protocol payloads with positional decoding and noting which ones have compatibility fallbacks. Add a concise inventory/table before proceeding, covering both core `Lotos.Zmq.Adt` instances and TaskSchedule payloads, with fallback status (for example, `WorkerState` has the old 8-frame fallback; most other payloads currently require exact/current frame shapes).

### Missing Items
- A current protocol payload inventory with fallback status for the positional `ToZmq`/`FromZmq` surfaces, including at least core task/router/backend/worker/logging payloads and TaskSchedule `WorkerState`/`ClientTask`.

### Suggestions
- In the inventory, distinguish route/envelope/discriminator frames from application payload frames so later docs/tests can clearly show where append-only changes are allowed.
