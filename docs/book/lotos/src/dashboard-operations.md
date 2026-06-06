# Dashboard Operations Manual

The Lotos dashboard is a read-only Vite + TypeScript view over the TaskSchedule demo runtime. It is for observing broker queues, worker capacity, reservations, heartbeats, and LogIngest counters; it does not submit tasks, retry work, mutate queues, restart services, or expose any broker control action.

Dashboard source and package-local development notes live in [`applications/dashboard/README.md`](../../../../applications/dashboard/README.md).

Use the commands below from the repository root. Long-running runtime commands should run in separate terminals.

## Roles and read-only boundaries

| Role | Default command | Uses | Exposes |
|------|-----------------|------|---------|
| Broker/server | `make task-schedule-server` | TaskSchedule broker config from `TASKSCHEDULE_BROKER_CONFIG`; ZMQ frontend `tcp://127.0.0.1:5555`; ZMQ backend `tcp://127.0.0.1:5556`; LogIngest runtime `tcp://127.0.0.1:5558` | Read-only HTTP info API at `http://127.0.0.1:8081/SimpleServer/...`; no HTTP write/control routes |
| Worker | `make task-schedule-worker` | Worker config from `TASKSCHEDULE_WORKER_CONFIG`; broker backend `tcp://127.0.0.1:5556`; LogIngest runtime `tcp://127.0.0.1:5558` | Heartbeats, task status, and task logs through the broker protocols; no dashboard HTTP server |
| Client submission | `make task-schedule-submit` | Client config from `TASKSCHEDULE_CLIENT_CONFIG`; task payload from `TASKSCHEDULE_TASK_JSON`; broker frontend `tcp://127.0.0.1:5555` | One task request and ACK result; use this role for writes instead of adding dashboard controls |
| Dashboard | `make dashboard-dev` | Browser fetches existing read-only HTTP endpoints under `DASHBOARD_API_ROOT` through the Vite proxy target `DASHBOARD_API_TARGET`; Vite binds `DASHBOARD_HOST` | Local Vite UI only, bound to `0.0.0.0:5173` by default; no task-control UI and no write API |
| mdBook docs | `make book-serve` | Static docs in `MDBOOK_DIR` | Local docs server at `http://<MDBOOK_HOST>:<MDBOOK_PORT>`; no runtime dependency |

The dashboard consumes only these read-only TaskSchedule endpoints by default:

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

4. Submit a demo task from another terminal when you want live work to appear:

   ```bash
   make task-schedule-submit
   ```

5. Start the dashboard in terminal 3:

   ```bash
   make dashboard-dev
   ```

   Open the Vite URL printed by the command, usually `http://127.0.0.1:5173` locally or the machine's LAN address on port `5173`.

6. Serve this manual locally if needed:

   ```bash
   make book-serve
   ```

The dashboard also works without live services: failed endpoint fetches render the sample/offline state instead of exposing write controls or requiring a server for static build verification.

## Configuration overrides

All examples use repository-root `make` targets so operators can see the defaults in `make help`.

### TaskSchedule runtime

```bash
make task-schedule-server TASKSCHEDULE_BROKER_CONFIG=applications/TaskSchedule/config/broker.json
make task-schedule-worker TASKSCHEDULE_WORKER_CONFIG=applications/TaskSchedule/config/worker.json
make task-schedule-submit \
  TASKSCHEDULE_CLIENT_CONFIG=applications/TaskSchedule/config/client.json \
  TASKSCHEDULE_TASK_JSON=applications/TaskSchedule/config/task-demo.json
```

Use matching frontend/backend/LogIngest addresses across those config files. The dashboard is read-only, so task payload changes always go through `TASKSCHEDULE_TASK_JSON` and `make task-schedule-submit`.

### Dashboard API and serving

```bash
make dashboard-dev DASHBOARD_HOST=0.0.0.0 DASHBOARD_API_TARGET=http://127.0.0.1:8081 DASHBOARD_API_ROOT=/SimpleServer
make dashboard-build DASHBOARD_API_BASE= DASHBOARD_API_ROOT=/SimpleServer DASHBOARD_API_TIMEOUT_MS=3500
make dashboard-preview DASHBOARD_API_BASE=http://127.0.0.1:8081 DASHBOARD_API_ROOT=/SimpleServer
```

- `DASHBOARD_HOST` defaults to `0.0.0.0` so the dev dashboard can be opened from another machine/container when networking permits.
- `DASHBOARD_API_TARGET` configures the Vite dev proxy target.
- `DASHBOARD_API_ROOT` defaults to `/SimpleServer` and must match the broker service name.
- `DASHBOARD_API_BASE` is used by built/previewed assets when you want direct browser fetches without the dev proxy.
- `DASHBOARD_API_TIMEOUT_MS` controls each read-only fetch timeout.

### mdBook

```bash
make book-build MDBOOK_DIR=docs/book/lotos
make book-serve MDBOOK_DIR=docs/book/lotos MDBOOK_HOST=0.0.0.0 MDBOOK_PORT=3004
```

## Design note

The dashboard intentionally uses a light operations theme rather than a dark control console. The near-white canvas, quiet borders, compact metric cards, and lavender-blue accent are meant to make queue pressure, stale heartbeats, reservations, and LogIngest warnings readable without suggesting that the page is an administrative control surface.

## Troubleshooting

### Dashboard shows `Offline sample`

- Confirm the broker/server is running and the HTTP port in `TASKSCHEDULE_BROKER_CONFIG` is `8081` or matches `DASHBOARD_API_TARGET` / `DASHBOARD_API_BASE`.
- Probe the read-only root directly:

  ```bash
  curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/info
  ```

- If the direct probe works but the Vite page does not, verify `DASHBOARD_HOST`, `DASHBOARD_API_ROOT=/SimpleServer`, and restart `make dashboard-dev` so the server/proxy config reloads.

### Workers do not appear

- Start the broker before workers so the worker can connect to the backend address.
- Check that `TASKSCHEDULE_WORKER_CONFIG` uses the same `loadBalancerBackendAddr` and `workerLogging.logIngestAddr` as the broker config.
- Probe worker state:

  ```bash
  curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/worker_stats
  ```

### Tasks do not appear

- Submit through the client role, not through the dashboard:

  ```bash
  make task-schedule-submit
  ```

- Keep `taskID` as `null` in task JSON; the broker assigns task ids.
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
```

Manual live dashboard verification is intentionally read-only:

1. Start server, worker, and dashboard with the startup order above.
2. Submit a task with `make task-schedule-submit`.
3. Refresh or wait for the dashboard poll interval; the status badge should move from sample/offline to live data.
4. Confirm the browser network panel only performs `GET` requests to the five dashboard endpoints listed above.
