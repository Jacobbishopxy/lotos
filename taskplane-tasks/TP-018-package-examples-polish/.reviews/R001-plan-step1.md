## Plan Review: Step 1: Plan adoption polish

### Verdict: REVISE

### Summary
The task requires a reviewable docs/examples outline before editing, but the current STATUS only repeats the Step 1 outcome checkboxes. Without the actual stale-doc findings, guide-structure decision, and metadata/config assessment, this checkpoint cannot validate that Step 2 will satisfy the adoption-polish mission.

### Issues Found
1. **[Severity: important]** — `PROMPT.md:71-77` makes Step 1 a plan-review checkpoint for the docs/examples outline, but `STATUS.md:21-26` contains only generic unchecked outcomes and no outline to review. Add a concise Step 1 plan in STATUS Notes (or equivalent) that lists the confusing/stale docs discovered after TP-015/016/017, states whether README-focused docs or a dedicated quickstart/build-your-own guide will be used, and identifies package metadata/sample config polish candidates or explicitly says none are needed.

### Missing Items
- A concrete docs/examples outline showing the intended new-adopter flow: quickstart/demo run, library extension points, scheduler/worker/client examples, and where retry/API/multi-worker-smoke status will be folded in.
- A package metadata/config assessment covering `lotos/lotos.cabal`, `applications/TaskSchedule/TaskSchedule.cabal`, and `applications/TaskSchedule/config/*`, even if the result is “no change”.
- A non-duplication decision for README vs `docs/task-schedule-mvp.md` vs any new guide, so Step 2 does not create overlapping long examples.

### Suggestions
- Keep the revised plan outcome-level: a short bullet list of target sections/files and acceptance checks is enough; no function-level implementation checklist is needed.
