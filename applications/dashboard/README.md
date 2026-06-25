# Lotos dashboard

This is the light Vite + TypeScript dashboard for the TaskSchedule demo runtime. It observes existing broker HTTP endpoints and renders useful sample/offline data when the backend is unavailable. When the TaskSchedule client bridge is running, it also exposes a narrow submit-only panel that sends a JSON envelope containing TOML to the bridge. It does not let the browser speak ZMQ, supply client/frontend/worker config, mutate queues, retry work, cancel/delete tasks, restart workers, or expose broker control actions.

For the complete operator guide, see the mdBook [Dashboard Operations Manual](../../docs/book/lotos/src/dashboard-operations.md).

## Quick start with live local data and submit UI

Run commands from the repository root. Keep the long-running services in separate terminals.

```bash
make dashboard-install                # once, if node_modules is absent
make task-schedule-server             # terminal 1; broker/info API on http://127.0.0.1:8081
make task-schedule-worker             # terminal 2; starts one worker
make task-schedule-client-bridge      # terminal 3; local POST /submit bridge on http://127.0.0.1:8090
make dashboard-dev                    # terminal 4; serves Vite on 127.0.0.1 and proxies /SimpleServer plus /submit
```

Open the Vite URL. The UI is grouped into tabs: **Overview**, **Submit Task**, **Workers**, **Tasks**, and **Logs / Diagnostics**, with a small always-visible status strip above them. Use the **Submit Task** tab to upload, paste/edit, load generated TOML, or fill the minimal template form for task name, shell command, marker path, and timeout. The Submit button sends only:

```json
{ "format": "toml", "taskToml": "schemaVersion = \"task-schedule/v2\"\n..." }
```

The bridge owns `clientId`, `loadBalancerFrontendAddr`, and `reqTimeoutSec`, then reuses the existing `ts-client` parse/validate/ACK path. A successful response means `accepted/enqueued`, not completed; completion appears later through worker/status/log polling.

Worker cards in the **Workers** tab show `Device CPU`, a system-wide CPU usage percentage sampled by the worker heartbeat. It is host/device utilization, not per-worker-process CPU. The **Tasks** tab groups queued, assigned, retry/failed, and garbage task rows; the **Logs / Diagnostics** tab groups LogIngest and runtime queue signals.

The dashboard polls these observer endpoints by default:

```text
/SimpleServer/info
/SimpleServer/tasks
/SimpleServer/worker_tasks
/SimpleServer/worker_stats
/SimpleServer/logs/stats
```

## Local development commands

Prefer root Make targets so runtime and dashboard defaults stay discoverable through `make help`:

```bash
make dashboard-install
make dashboard-dev
make dashboard-build
make dashboard-preview
make smoke-dashboard-bridge
make smoke-dashboard-browser  # optional real-browser click smoke; requires BROWSER_BIN or Chrome/Chromium on PATH
```

Equivalent package-local commands are available when working only inside this directory:

```bash
npm install
npm run dev
npm run build
npm run preview
```

`npm run build` performs `tsc --noEmit` and `vite build`; it does not require live TaskSchedule services.

## Configuration

Root Make targets pass Vite environment variables for the dev host, API root, read proxy target, bridge proxy target/path, direct API/bridge bases, and request timeouts:

```bash
make dashboard-dev \
  DASHBOARD_HOST=127.0.0.1 \
  DASHBOARD_API_TARGET=http://127.0.0.1:8081 \
  DASHBOARD_API_ROOT=/SimpleServer \
  DASHBOARD_BRIDGE_TARGET=http://127.0.0.1:8090 \
  DASHBOARD_BRIDGE_PATH=/submit
make dashboard-build DASHBOARD_API_BASE= DASHBOARD_API_ROOT=/SimpleServer DASHBOARD_BRIDGE_BASE= DASHBOARD_BRIDGE_PATH=/submit
# Direct bases are baked at build time; rebuild with them before previewing.
make dashboard-build DASHBOARD_API_BASE=http://127.0.0.1:8081 DASHBOARD_BRIDGE_BASE=http://127.0.0.1:8090 \
  && make dashboard-preview
# Direct bases also require same-origin serving or external CORS/reverse-proxy support.
```

- `DASHBOARD_HOST` defaults to `127.0.0.1` because the dev server now proxies a submit endpoint. Override deliberately if you need remote access. From the repo root, `TASKSCHEDULE_BIND_ALL=1 make dashboard-dev` uses `TASKSCHEDULE_BIND_HOST` (default `0.0.0.0`) for the dev server host.
- `DASHBOARD_API_TARGET` / `VITE_TASKSCHEDULE_API_TARGET` configures the Vite dev proxy target for observer endpoints.
- `DASHBOARD_API_ROOT` / `VITE_TASKSCHEDULE_API_ROOT` defaults to `/SimpleServer`.
- `DASHBOARD_API_BASE` / `VITE_TASKSCHEDULE_API_BASE` is used by built assets when fetching observer endpoints directly. The broker observer API does not add browser CORS headers itself, so built/preview assets need same-origin serving or an external CORS/reverse proxy for direct observer fetches.
- `DASHBOARD_BRIDGE_TARGET` configures the Vite dev proxy target for `/submit`.
- `DASHBOARD_BRIDGE_BASE` / `VITE_TASKSCHEDULE_BRIDGE_BASE` is used by built/preview assets when posting directly to the bridge. Direct browser posts are accepted only from the bridge config's `bridgeAllowedOrigins`; use the dev proxy or a same-origin reverse proxy for other deployments.
- `DASHBOARD_API_TIMEOUT_MS` and `DASHBOARD_BRIDGE_TIMEOUT_MS` control read and submit timeouts.
- `applications/TaskSchedule/config/client-bridge.json` owns bridge-side `bridgeAllowedOrigins` and `bridgeAllowNoOrigin`. Keep `bridgeAllowNoOrigin=true` for local curl/dev-proxy smoke; set it to `false` and enumerate exact origins for non-loopback deployments. The root `TASKSCHEDULE_BIND_ALL=1` flag generates public-bind bridge configs under `.tmp/task-schedule-bind-all-config/` with `bridgeAllowNoOrigin=false`.

## Troubleshooting

- If the UI says `Offline sample`, confirm the broker is running and probe `curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/info`.
- If submit returns `validation-error`, fix the TOML contract; at least one `[[steps]]` entry is required and `schemaVersion` must be `task-schedule/v2`.
- If submit returns `ack-timeout`, the bridge parsed the TOML but did not receive a broker ACK before `reqTimeoutSec`; check the server/frontend address in the bridge config.
- If the probe works but the browser fetch fails in dev mode, restart `make dashboard-dev` after changing `DASHBOARD_HOST`, `DASHBOARD_API_TARGET`, `DASHBOARD_API_ROOT`, `DASHBOARD_BRIDGE_TARGET`, or `DASHBOARD_BRIDGE_PATH`; Vite reads server/proxy settings at startup.
- Use `make smoke-single`, `make smoke-multi`, or `make smoke-dashboard-bridge` from the repository root for bounded end-to-end runtime evidence.
