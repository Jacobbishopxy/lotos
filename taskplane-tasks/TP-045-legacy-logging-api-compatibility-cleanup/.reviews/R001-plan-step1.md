## Plan Review: Step 1: Plan compatibility surface

### Verdict: REVISE

### Summary
The task requirements are clear, but the submitted STATUS.md does not yet contain a Step 1 compatibility-surface plan to review; it only repeats the prompt checklist. For a public config/API compatibility cleanup, Step 1 needs to record the concrete inventory, naming decisions, JSON compatibility rules, and migration examples before implementation starts.

### Issues Found
1. **[Severity: important]** — No concrete compatibility plan is recorded for the plan-review checkpoint. `STATUS.md` lines 24-27 still contain only unchecked prompt-level outcomes, not the inventory of legacy names, chosen replacements, or migration examples required by `PROMPT.md` lines 67-69. Fix: add the Step 1 plan/discovery notes to STATUS.md (or another referenced artifact) and resubmit for review before Step 2.
2. **[Severity: important]** — The plan does not define old/new JSON conflict and default-derivation behavior. This cleanup touches `infoStorage.loggingAddr`, `infoStorage.loggingsBufferSize`, `loadBalancerLoggingAddr`, `logIngest`, and `workerLogging`; if both legacy and new keys appear, or if nested LogIngest config is partial, implementation needs an explicit precedence/default rule to avoid silently changing endpoints. Fix: specify accepted old/new keys, required vs optional fields, precedence when both are present, and how LogIngest defaults derive for old-only, new-only, and mixed configs.

### Missing Items
- Actual inventory of every public/code/docs/config occurrence, including exported Haskell record fields in `Lotos.Zmq.Config`, `TaskAcceptorAPI.taPubTaskLogging`, checked-in TaskSchedule JSON defaults, README, mdBook pages, and legacy compatibility docs.
- Chosen new names and compatibility strategy for both JSON and Haskell API surfaces: whether old record fields remain exported with deprecation comments, whether new fields are added, and whether any legacy names become parse-only aliases.
- Broker and worker migration examples showing old JSON, preferred new JSON, and mixed compatibility behavior.

### Suggestions
- Include a short table mapping `old name -> new name -> compatibility behavior -> docs/tests to update`; that will make the Step 2 implementation and Step 3 tests much easier to audit.
