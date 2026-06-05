# Lotos dashboard

This is the light, read-only Vite + TypeScript dashboard for the TaskSchedule demo runtime. It observes existing broker HTTP endpoints and renders useful sample/offline data when the backend is unavailable. It does not submit tasks, mutate queues, retry work, or expose broker control actions.

For the complete operator guide, see the mdBook [Dashboard Operations Manual](../../docs/book/lotos/src/dashboard-operations.md).

## Quick start with live local data

Run commands from the repository root. Keep the long-running services in separate terminals.

```bash
make dashboard-install                # once, if node_modules is absent
make task-schedule-server             # terminal 1; starts broker/info API on http://127.0.0.1:8081
make task-schedule-worker             # terminal 2; starts one worker
make task-schedule-submit             # optional demo task submission
make dashboard-dev                    # terminal 3; opens Vite on 127.0.0.1 and proxies /SimpleServer
```

The dashboard polls these read-only endpoints by default:

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

Root Make targets pass Vite environment variables for the API root, proxy target, direct API base, and request timeout:

```bash
make dashboard-dev DASHBOARD_API_TARGET=http://127.0.0.1:8081 DASHBOARD_API_ROOT=/SimpleServer
make dashboard-build DASHBOARD_API_BASE= DASHBOARD_API_ROOT=/SimpleServer DASHBOARD_API_TIMEOUT_MS=3500
make dashboard-preview DASHBOARD_API_BASE=http://127.0.0.1:8081 DASHBOARD_API_ROOT=/SimpleServer
```

- `DASHBOARD_API_TARGET` / `VITE_TASKSCHEDULE_API_TARGET` configures the Vite dev proxy target.
- `DASHBOARD_API_ROOT` / `VITE_TASKSCHEDULE_API_ROOT` defaults to `/SimpleServer`.
- `DASHBOARD_API_BASE` / `VITE_TASKSCHEDULE_API_BASE` is used by built assets when fetching directly.
- `DASHBOARD_API_TIMEOUT_MS` / `VITE_TASKSCHEDULE_API_TIMEOUT_MS` defaults to `3500`.

## Troubleshooting

- If the UI says `Offline sample`, confirm the broker is running and probe `curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/info`.
- If the probe works but the browser fetch fails in dev mode, restart `make dashboard-dev` after changing `DASHBOARD_API_TARGET` or `DASHBOARD_API_ROOT`; Vite reads proxy settings at startup.
- If no tasks appear, submit work through `make task-schedule-submit`. The dashboard intentionally has no task submission or control UI.
- Use `make smoke-single` or `make smoke-multi` from the repository root for bounded end-to-end runtime evidence.
