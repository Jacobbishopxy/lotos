# Dashboard Operations Manual

The Lotos dashboard is a Vite + TypeScript view over the TaskSchedule demo runtime. It observes broker queues, worker capacity, reservations, heartbeats, and LogIngest counters through the existing observer endpoints. When the TaskSchedule client bridge is running, the dashboard also exposes one submit-only TOML panel that posts a JSON envelope to the bridge.

The submit path is intentionally narrow: the browser sends only `{ "format": "toml", "taskToml": "..." }`; it does not speak ZMQ and cannot provide client id, frontend address, worker id, ACK timeout, or other client/worker/broker config. The bridge reuses the shared `ts-client` TOML parse/validate helpers and submits through `mkClientService` / `sendTaskRequest`. It does not add retry, cancel, delete, queue mutation, worker restart, or scheduler-control actions.

Dashboard source and package-local development notes live in [`applications/dashboard/README.md`](../../../../applications/dashboard/README.md). The implementation comparison that selected this hybrid design is recorded in [Dashboard Client Bridge Experiment](dashboard-client-bridge-experiment.md).

Use the commands below from the repository root. Long-running runtime commands should run in separate terminals.

## Roles and boundaries

| Role | Default command | Uses | Exposes |
|------|-----------------|------|---------|
| Broker/server | `make task-schedule-server` | TaskSchedule broker config from `TASKSCHEDULE_BROKER_CONFIG`; ZMQ frontend `tcp://127.0.0.1:5555`; ZMQ backend `tcp://127.0.0.1:5556`; LogIngest runtime `tcp://127.0.0.1:5558` | Observer HTTP info API at `http://127.0.0.1:8081/SimpleServer/...`; no HTTP write/control routes |
| Worker | `make task-schedule-worker` | Worker config from `TASKSCHEDULE_WORKER_CONFIG`; broker backend `tcp://127.0.0.1:5556`; LogIngest runtime `tcp://127.0.0.1:5558` | Heartbeats, task status, and task logs through broker protocols; no dashboard HTTP server |
| CLI client submission | `make task-schedule-submit` / `make task-validate` | Client config from `TASKSCHEDULE_CLIENT_CONFIG`; task payload from `TASKSCHEDULE_TASK_TOML`; broker frontend `tcp://127.0.0.1:5555` for submit only | One task request and ACK result for non-dashboard submissions |
| Client bridge | `make task-schedule-client-bridge` | Bridge config from `TASKSCHEDULE_CLIENT_BRIDGE_CONFIG`; server-owned `ClientServiceConfig`; local bind `127.0.0.1:8090` by default | `POST /submit` for TOML envelopes; structured validation, ACK-timeout, and accepted/enqueued JSON responses |
| Dashboard | `make dashboard-dev` | Browser fetches observer endpoints under `DASHBOARD_API_ROOT` through `DASHBOARD_API_TARGET`; browser posts `/submit` through `DASHBOARD_BRIDGE_TARGET`; Vite binds `DASHBOARD_HOST` | Local Vite UI, bound to `127.0.0.1:5173` by default; submit-only panel plus observer views; no control-plane UI |
| mdBook docs | `make book-serve` | Static docs in `MDBOOK_DIR` | Local docs server at `http://<MDBOOK_HOST>:<MDBOOK_PORT>`; no runtime dependency |

The worker card's `Device CPU` meter shows system-wide CPU usage sampled by the worker heartbeat. It is host/device utilization for scheduling and operations visibility, not per-worker-process CPU.

The dashboard consumes these TaskSchedule observer endpoints by default:

```text
/SimpleServer/info
/SimpleServer/tasks
/SimpleServer/worker_tasks
/SimpleServer/worker_stats
/SimpleServer/logs/stats
```

`/info` supplies worker liveness, capacity reservations, queue snapshots, and cached task state. `/tasks`, `/worker_tasks`, and `/worker_stats` provide focused task and worker views. `/logs/stats` is LogIngest accounting only and remains separate from runtime handoff queue depth.

For deeper probes such as `/logs/recent`, `/logs/worker/<workerId>`, `/logs/task/<taskUuid>`, and `/garbage`, use the [Operations Runbook](operations.md) or direct `curl` commands rather than expanding dashboard scope.

## Startup order

1. Optional, install dashboard dependencies once:

   ```bash
   make dashboard-install
   ```

2. Start the broker/server in terminal 1:

   ```bash
   make task-schedule-server
   ```

   The foreground console intentionally stays quiet: it prints a compact alive line while detailed broker logs continue under `logs/taskScheduleServer.log` and runtime state is visible in the dashboard.

3. Start one or more workers in terminal 2:

   ```bash
   make task-schedule-worker
   ```

   Worker terminals follow the same pattern: a compact alive line on stdout, detailed file logs under `logs/taskScheduleWorker.log`, and task/runtime state through the dashboard and `/logs/*` endpoints.

4. Start the client bridge in terminal 3 when the dashboard submit panel should be enabled:

   ```bash
   make task-schedule-client-bridge
   ```

   The checked-in bridge config binds to `127.0.0.1:8090`, uses `dashboardClientBridge_1` as its server-owned client id, points at the broker frontend, caps submit JSON bodies at 64 KiB, and allowlists local Vite dev/preview origins. `bridgeAllowNoOrigin` is kept enabled for local curl/dev-proxy smoke; disable it and enumerate exact `bridgeAllowedOrigins` for non-loopback deployments.

5. Start the dashboard in terminal 4:

   ```bash
   make dashboard-dev
   ```

   Open the Vite URL printed by the command, usually `http://127.0.0.1:5173`. The dashboard dev server proxies `/SimpleServer` to the broker info API and `/submit` to the client bridge.

6. Submit through either path:

   - Dashboard: upload, paste/edit, load the generated sample TOML, or use the minimal template form to set task name, shell command, marker path, and timeout, then click **Submit** once. No confirmation modal is shown.
   - CLI: `make task-schedule-submit` remains available for non-dashboard submissions.

7. Serve this manual locally if needed:

   ```bash
   make book-serve
   ```

The dashboard also works without live services: failed observer endpoint fetches render the sample/offline state, and submit attempts return bridge/timeout/validation feedback instead of exposing control actions.

## Submit API shape

The dashboard posts the following browser envelope to the bridge:

```json
{
  "format": "toml",
  "taskToml": "schemaVersion = \"task-schedule/v2\"\nname = \"...\"\n..."
}
```

Success means the broker accepted/enqueued the task and sent an ACK; it does not mean worker completion:

```json
{
  "ok": true,
  "status": "accepted",
  "message": "accepted/enqueued",
  "taskName": "..."
}
```

Validation, unsupported-format, and timeout failures are also structured JSON:

```json
{ "ok": false, "status": "validation-error", "message": "at least one [[steps]] entry is required", "taskName": null }
{ "ok": false, "status": "unsupported-format", "message": "unsupported format: only toml is supported", "taskName": null }
{ "ok": false, "status": "ack-timeout", "message": "no ACK received before reqTimeoutSec (5s)", "taskName": null }
```

The bridge rejects unsupported formats, malformed JSON/TOML, empty `taskToml`, oversize bodies, disallowed browser origins, and unexpected request fields such as `clientId`, `loadBalancerFrontendAddr`, `workerId`, or nested client config. Origin policy is operator-configurable through `bridgeAllowedOrigins` and `bridgeAllowNoOrigin` in the bridge config. Submit attempts are audited to `logs/taskScheduleClientBridge.log` without logging full TOML bodies.

## Configuration overrides

All examples use repository-root `make` targets so operators can see the defaults in `make help`.

### TaskSchedule runtime

```bash
make task-schedule-server TASKSCHEDULE_BROKER_CONFIG=applications/TaskSchedule/config/broker.json
make task-schedule-worker TASKSCHEDULE_WORKER_CONFIG=applications/TaskSchedule/config/worker.json
make task-schedule-client-bridge TASKSCHEDULE_CLIENT_BRIDGE_CONFIG=applications/TaskSchedule/config/client-bridge.json
make task-schedule-submit \
  TASKSCHEDULE_CLIENT_CONFIG=applications/TaskSchedule/config/client.json \
  TASKSCHEDULE_TASK_TOML=applications/TaskSchedule/config/task-demo.toml
make task-validate TASKSCHEDULE_TASK_TOML=applications/TaskSchedule/config/task-demo.toml
make task-template TASKSCHEDULE_TASK_TEMPLATE_OUT=tasks/new-task.toml
```

Use matching frontend/backend/LogIngest addresses across those config files. The checked-in configs default to loopback binds. To opt into public binds without editing checked-in JSON, pass `TASKSCHEDULE_BIND_ALL=1` to the same Make targets; this generates `.tmp/task-schedule-bind-all-config/*.json` with broker TCP binds, broker HTTP `httpHost`, bridge bind, and dashboard dev host set from `TASKSCHEDULE_BIND_HOST` (default `0.0.0.0`). Set `TASKSCHEDULE_CONNECT_HOST=<server-ip-or-dns>` to the concrete address workers, clients, and the bridge use to connect back to the broker. Do not use `0.0.0.0` as a remote connect address.

The bridge defaults to loopback bind; non-loopback bridge exposure should be an explicit operator decision because it enables task submission. For non-loopback deployments, set `bridgeAllowNoOrigin` to `false`, list exact browser origins in `bridgeAllowedOrigins`, and prefer a same-origin reverse proxy over direct cross-origin bridge posts. Generated `TASKSCHEDULE_BIND_ALL=1` bridge configs set `bridgeAllowNoOrigin=false` and include loopback plus `TASKSCHEDULE_CONNECT_HOST` / `TASKSCHEDULE_DASHBOARD_ORIGIN_HOST` dashboard origins for ports 5173 and 4173.

### Dashboard API and serving

```bash
make dashboard-dev \
  DASHBOARD_HOST=127.0.0.1 \
  DASHBOARD_API_TARGET=http://127.0.0.1:8081 \
  DASHBOARD_API_ROOT=/SimpleServer \
  DASHBOARD_BRIDGE_TARGET=http://127.0.0.1:8090 \
  DASHBOARD_BRIDGE_PATH=/submit
TASKSCHEDULE_BIND_ALL=1 TASKSCHEDULE_CONNECT_HOST=<server-ip-or-dns> make dashboard-dev
make dashboard-build DASHBOARD_API_BASE= DASHBOARD_API_ROOT=/SimpleServer DASHBOARD_BRIDGE_BASE= DASHBOARD_BRIDGE_PATH=/submit
# Direct bases are baked at build time; rebuild with them before previewing.
make dashboard-build DASHBOARD_API_BASE=http://127.0.0.1:8081 DASHBOARD_BRIDGE_BASE=http://127.0.0.1:8090 \
  && make dashboard-preview
# Direct bases also require same-origin serving or external CORS/reverse-proxy support.
```

- `DASHBOARD_HOST` defaults to `127.0.0.1` because the dev server proxies submit traffic. Override deliberately if you need remote access. `TASKSCHEDULE_BIND_ALL=1` makes the Make target use `TASKSCHEDULE_BIND_HOST` for the dashboard dev host.
- `DASHBOARD_API_TARGET` configures the Vite dev proxy target for observer endpoints.
- `DASHBOARD_API_ROOT` defaults to `/SimpleServer` and must match the broker service name.
- `DASHBOARD_API_BASE` is used by built/previewed assets when you want direct browser fetches without the dev proxy. The broker observer API itself does not add browser CORS headers, so direct preview/build fetches need same-origin serving or an external CORS/reverse proxy.
- `DASHBOARD_BRIDGE_TARGET` configures the Vite dev proxy target for `/submit`.
- `DASHBOARD_BRIDGE_BASE` is used by built/previewed assets when posting directly to the bridge. Direct browser posts are accepted only from origins listed in the bridge config; use the dev proxy or a same-origin reverse proxy for other deployments.
- `DASHBOARD_API_TIMEOUT_MS` and `DASHBOARD_BRIDGE_TIMEOUT_MS` control observer fetch and submit timeouts.

### mdBook

```bash
make book-build MDBOOK_DIR=docs/book/lotos
make book-serve MDBOOK_DIR=docs/book/lotos MDBOOK_HOST=0.0.0.0 MDBOOK_PORT=3004
```

## Design note

The dashboard intentionally uses a light operations theme rather than a dark control console. The near-white canvas, quiet borders, compact metric cards, and lavender-blue accent are meant to make queue pressure, stale heartbeats, reservations, submit ACK state, and LogIngest warnings readable without suggesting that the page is an administrative control surface.

## Troubleshooting

### Dashboard shows `Offline sample`

- Confirm the broker/server is running and the HTTP port in `TASKSCHEDULE_BROKER_CONFIG` is `8081` or matches `DASHBOARD_API_TARGET` / `DASHBOARD_API_BASE`.
- Probe the observer root directly:

  ```bash
  curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/info
  ```

- If the direct probe works but the Vite page does not, verify `DASHBOARD_HOST`, `DASHBOARD_API_ROOT=/SimpleServer`, and restart `make dashboard-dev` so the server/proxy config reloads.

### Submit panel returns `validation-error`

- Confirm the request format is TOML and the contract includes `schemaVersion = "task-schedule/v2"`, `name`, `[retry]`, `[schedule]`, and at least one `[[steps]]` entry.
- Omit `taskID`; the broker assigns task ids.
- Do not include browser-side `clientId`, `loadBalancerFrontendAddr`, `workerId`, or nested client config fields.
- If posting directly from built/preview assets, use a local dashboard origin allowed by the bridge (`127.0.0.1`/`localhost` Vite dev or preview ports) or route through a same-origin proxy.

### Submit panel returns `ack-timeout`

- The TOML parsed and validation passed, but the bridge did not receive a broker ACK before `reqTimeoutSec`.
- Start the broker first, confirm `TASKSCHEDULE_CLIENT_BRIDGE_CONFIG` points at the broker frontend, and check `logs/taskScheduleClientBridge.log` plus `logs/taskScheduleClient.log`.

### Workers do not appear

- Start the broker before workers so the worker can connect to the backend address.
- Check that `TASKSCHEDULE_WORKER_CONFIG` uses the same `loadBalancerBackendAddr` and `workerLogging.logIngestAddr` as the broker config.
- Probe worker state:

  ```bash
  curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/worker_stats
  ```

### Tasks do not appear after accepted/enqueued

- ACK means accepted/enqueued, not completed. Wait for the dashboard poll interval and the broker info snapshot interval.
- Check worker logs, marker/output files, `/SimpleServer/worker_tasks`, `/SimpleServer/tasks`, `/SimpleServer/logs/stats`, and deeper `/logs/task/<taskUuid>` probes when needed.
- Use [Runtime Failure Runbook](runtime-failures.md) if tasks remain queued, workers go stale, reservations look conservative, or handoff queues show sustained warning/critical state.

### Log counters look different from runtime queue depth

This is expected. `/logs/stats` reports LogIngest accepted/duplicate/gap/drop/rejected counters. Runtime handoff queue depth is in `/SimpleServer/info.runtimeQueueStats`. Do not use LogIngest counters as proof that task/status protocol frames were dropped.

## Smoke and manual verification

Static documentation/dashboard checks do not require live services:

```bash
make help
make book-build
make dashboard-build
```

Runtime smoke checks start and clean up tracked services, write evidence under `.tmp/`, and verify endpoint shape plus worker execution evidence:

```bash
make smoke-single
make smoke-multi
make smoke-dashboard-bridge
make smoke-dashboard-browser  # requires BROWSER_BIN or Chrome/Chromium on PATH
```

`make smoke-dashboard-browser` runs the dashboard bridge smoke with `SMOKE_BROWSER_CLICK=1`, launching Chrome/Chromium through `scripts/dashboard-submit-browser-smoke.mjs`. The helper fills the dashboard template form, clicks **Generate TOML**, clicks **Submit**, waits for the accepted/enqueued UI state, and saves `browser-submit-result.json` plus `browser-submit-screenshot.png` in the evidence directory. Set `BROWSER_BIN=/path/to/chrome` when the browser is not on `PATH`.

Manual live dashboard verification:

1. Start server, worker, bridge, and dashboard with the startup order above.
2. In the dashboard submit panel, generate TOML from the minimal template form or upload/paste TOML, then click **Submit** once.
3. Confirm the submit panel shows `accepted` / `accepted/enqueued` or a structured `validation-error` / `ack-timeout` response.
4. Wait for dashboard polling; the task should become observable through the existing task/worker/status/log views, and worker completion evidence should appear later than the ACK.
5. Confirm the browser network panel uses one submit `POST /submit` plus observer `GET` requests to the endpoints listed above; there should be no retry/cancel/delete/worker/queue-control requests.
