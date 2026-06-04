## Plan Review: Step 1: Inventory worker EventLoop failure modes

### Verdict: REVISE

### Summary
No actual Step 1 inventory/plan was submitted for review. `STATUS.md` still only repeats the task-level Step 1 checkboxes, so the required failure-mode semantics and test mapping are not yet documented enough to guide implementation.

### Issues Found
1. **[Severity: important]** — `STATUS.md:25-30` does not enumerate the required failure paths; it only lists the prompt checklist. Add a concrete inventory covering stopped backend/log loops, callback exceptions, mailbox-full behavior, broker disconnect/send failures, and context termination/`ETERM` paths.
2. **[Severity: important]** — The plan does not decide per-failure behavior. Before Step 2, document which cases are logged and ignored, retried, made visible to task/status semantics, or treated as loop/task-terminal failures so implementation does not accidentally couple logging failures to backend progress.
3. **[Severity: important]** — The plan does not map each failure mode to regression coverage. Add a failure-mode-to-test matrix, including backend stopped-loop behavior, logging stopped-loop/drop accounting, and context teardown/forked action behavior.

### Missing Items
- A source-grounded summary of the current EventLoop command/callback/mailbox APIs and where they are used in `LBW.hs`, `LBW/LogTransport.hs`, and `Internal/WorkerRuntime.hs`.
- Explicit handling intent for `ETERM`/context termination versus ordinary broker disconnect or send failures.
- Explicit separation between logging transport failures and task/status backend semantics.

### Suggestions
- Keep the inventory concise: a table with columns for failure mode, trigger/source, desired behavior, affected component, and planned test is enough.
