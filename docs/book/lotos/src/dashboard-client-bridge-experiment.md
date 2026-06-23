# Dashboard Client Bridge Experiment

This page records the June 2026 experiment that compared two implementation lanes for adding a submit-only TaskSchedule path to the dashboard.

## Experiment goal

The target was a runnable operator flow:

1. start the TaskSchedule broker/server;
2. start at least one worker;
3. start a local client bridge;
4. open the dashboard;
5. upload, paste/edit, or generate a TOML task contract;
6. click **Submit** once;
7. receive a structured `accepted/enqueued`, `validation-error`, or `ack-timeout` response;
8. observe later task and log state through the existing dashboard observer panels.

The frozen boundary was submit-only. The browser must send only:

```json
{ "format": "toml", "taskToml": "schemaVersion = \"task-schedule/v2\"\n..." }
```

It must not speak ZMQ, provide client ids, frontend addresses, worker ids, ACK timeouts, or expose retry/cancel/delete/queue/worker/scheduler controls.

## Candidates compared

| Candidate | Worktree | Approach |
|-----------|----------|----------|
| Main-agent plus subagents | `lotos-exp-client-bridge-subagents` | One owner implemented the product path while bounded subagents handled recon/review lanes. |
| Taskplane series | `lotos-exp-client-bridge-taskplane` | Four Taskplane packets split work into shared helpers, bridge service, dashboard UI, and integrated smoke/docs evidence. |

## Judgment summary

| Metric | Subagents lane | Taskplane lane | Winner |
|--------|----------------|----------------|--------|
| Task completeness | Working dashboard-facing proxy submit path, bridge, docs, smoke | Working bridge/dashboard path, richer template form, task artifacts | Slight subagents |
| Security boundary | Strict JSON field allowlist, request-size limit, loopback default, forbidden-origin smoke | Server-side client config, but unknown JSON fields ignored, no bridge CORS middleware, dev host defaulted wider | Subagents |
| Verification | Bridge tests plus dashboard build, mdBook build, ZMQ ACK tests, live smoke through Vite `/submit` proxy | More task-local unit tests and claimed `make ci-check`; smoke posted directly to bridge rather than dashboard proxy | Tie / slight subagents |
| Maintainability | Smaller product diff, fewer artifacts, direct WAI bridge code | Cleaner typed status/config model and richer task trail, but larger surface | Tie |
| Operator UX | Upload/edit/sample TOML submit panel | Better generated-template form | Taskplane |
| Process efficiency | About 57 minutes; complete session telemetry around `$20.81`; one review/fix cycle | About 7h47 wall time; runtime repair incidents; incomplete/conflicting cost telemetry | Subagents |
| Integration hygiene | Product commit plus experiment prompt commit | Many merge/chore/task-artifact commits and committed Taskplane packet history | Subagents |

Final scores from the comparison were:

- **Subagents lane: 8.3 / 10**
- **Taskplane lane: 7.0 / 10**

The selected base was the **subagents lane** because it better protected the browser/bridge security boundary and proved the actual dashboard-facing dev-proxy submit path. The Taskplane lane contributed useful polish rather than becoming the merge base.

## Final merged design

The final implementation keeps the subagents bridge semantics and ports the Taskplane UX/test improvements that were worth preserving:

- the dashboard submit panel now supports paste/edit, file import, and a small generated-template form for task name, shell command, marker path, and timeout;
- `applications/dashboard/src/sampleData.ts` owns the sample TOML/template generator used by the UI;
- the bridge request remains strict: only `format` and `taskToml` are accepted;
- browser-supplied `clientId`, `loadBalancerFrontendAddr`, worker ids, nested client config, and other unexpected fields are rejected before submission;
- the bridge defaults to `127.0.0.1:8090`, audits submit attempts without logging full TOML bodies, maps accepted ACKs distinctly from worker completion, and exposes configurable `bridgeAllowedOrigins` / `bridgeAllowNoOrigin` for non-loopback deployments;
- `TaskSchedule:test:test-client-submission` adds focused TOML parse/validation coverage and is included in `CI_TEST_TARGETS`;
- `make smoke-dashboard-browser` adds real browser click automation for the generated-template form and Submit button when Chrome/Chromium is available.

## Final verification profile

The minimum verification profile for this feature is:

```bash
cabal build TaskSchedule:exe:ts-client TaskSchedule:exe:ts-client-bridge
cabal test TaskSchedule:test:test-client-submission TaskSchedule:test:test-client-bridge
npm --prefix applications/dashboard run build
make book-build
make smoke-dashboard-bridge
make smoke-dashboard-browser  # requires BROWSER_BIN or Chrome/Chromium on PATH
```

`make smoke-dashboard-bridge` is the strongest dependency-free runtime proof. It starts the tracked services, submits through the dashboard-facing `/submit` path, verifies structured validation/timeout/accepted responses, observes task state through existing read-only endpoints, and preserves evidence under `.tmp/client-bridge-dashboard-smoke/<run-id>/`.

`make smoke-dashboard-browser` removes the remaining UI-click coverage gap when a browser is available. It drives the real dashboard with Chrome/Chromium, fills the generated-template form, clicks **Generate TOML**, clicks **Submit**, and stores browser result/screenshot evidence alongside the normal smoke artifacts.

## Lessons learned

- For cross-boundary features where security and runtime smoke are more important than task bookkeeping, one owner plus focused review subagents produced the cleaner result.
- Taskplane was useful for decomposing work and forcing review gates, but the overhead was high for a serial feature with shared files.
- The best hybrid was not a full merge of either lane: keep the safer bridge and smoke path, then selectively port the richer UI/template and focused helper tests.
- Any future dashboard write capability needs a new threat model. The current dashboard remains observer-first with exactly one submit-only TOML handoff.
