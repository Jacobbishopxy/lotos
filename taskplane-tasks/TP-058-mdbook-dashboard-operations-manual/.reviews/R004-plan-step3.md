## Plan Review: Step 3: README/dashboard docs alignment

### Verdict: APPROVE

### Summary
I treated the Step 3 STATUS bullets as the implementation plan, consistent with the earlier reviews, because no separate plan artifact is present. The plan covers the required alignment surfaces: top-level README, dashboard-local README, and cross-links back to the mdBook manual; paired with the prompt's Step 3 wording, this is sufficient at outcome granularity.

### Issues Found
- None.

### Missing Items
- None blocking.

### Suggestions
- Make the top-level README path explicitly use the new `make` targets for the shortest live-dashboard flow (`task-schedule-server`, `task-schedule-worker`, `task-schedule-submit`, `dashboard-dev`) rather than preserving older direct `cabal run` startup text as the primary path.
- Since `applications/dashboard/README.md` is currently absent, include the local dev/build/preview commands and the API override variables (`DASHBOARD_API_TARGET`, `DASHBOARD_API_ROOT`, `DASHBOARD_API_BASE`, `DASHBOARD_API_TIMEOUT_MS`) while cross-linking the full mdBook manual for operations details.
