## Code Review: Step 3: Makefile/README integration

### Verdict: APPROVE

### Summary
The Makefile now exposes dashboard API defaults, threads them into the Vite build/dev/preview commands, and keeps `make help` aligned with the new live-data workflow. README documents the expected TaskSchedule backend, default `/SimpleServer` dev proxy, direct API-base option, and offline/sample fallback. No configured typecheck/lint/format commands were found in `.pi/taskplane-config.json` or a root `package.json`; I additionally ran `make help` and `make -n dashboard-build dashboard-dev dashboard-preview`, both successfully.

### Issues Found
None.

### Pattern Violations
None.

### Test Gaps
None for this Makefile/README step; Step 4 already tracks running `make dashboard-build` and optional live-fetch confirmation.

### Suggestions
- Consider adding a short README note that `DASHBOARD_API_BASE` is baked at Vite build time, while `DASHBOARD_API_TARGET` only affects the dev proxy.
