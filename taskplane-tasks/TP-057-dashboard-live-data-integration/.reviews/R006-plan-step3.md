## Plan Review: Step 3: Makefile/README integration

### Verdict: APPROVE

### Summary
The Step 3 checklist in STATUS.md matches the required integration outcomes: refine dashboard Make targets, update README usage, and keep `make help` aligned. This is a small documentation/Makefile step, so the concise plan is sufficient as long as implementation keeps the default `http://127.0.0.1:8081` backend and offline fallback behavior explicit.

### Issues Found
None.

### Missing Items
- None.

### Suggestions
- In the Makefile/help text, surface the dashboard API target/default and any override env names used by Vite (for example the existing `DASHBOARD_API_TARGET` / `VITE_TASKSCHEDULE_API_*` conventions) so users do not have to inspect `vite.config.ts`.
- In README usage, explicitly state that the TaskSchedule server info API is optional for dashboard build/preview, that live reads use the `/SimpleServer` endpoints under `http://127.0.0.1:8081` by default, and that the UI falls back to sample/offline data when those read-only endpoints are unavailable.
