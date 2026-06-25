# Lotos

Lotos is a Haskell/Cabal workspace for a ZeroMQ-backed task load-balancer library and a concrete `TaskSchedule` demo cluster. The demo schedules TOML-authored shell-command tasks onto workers, exposes read-only runtime state over HTTP, and includes a light dashboard with an optional submit-only client bridge.

## What is in this repo

| Path | Purpose |
|---|---|
| `lotos/` | Reusable core library: logging, concurrent process execution, STM helpers, and the public `Lotos.Zmq` load-balancer facade. |
| `applications/TaskSchedule/` | Example broker, worker, client, and dashboard submit bridge built on `lotos`. |
| `applications/dashboard/` | Vite + TypeScript observer dashboard with offline sample data and submit-only TOML panel. |
| `examples/minimal-scheduler/` | Small public-API-only scheduler example for new library adopters. |
| `docs/book/lotos/` | mdBook architecture, operations, runbooks, release notes, and verification docs. |
| `scripts/` | Bounded smoke/demo helpers. |

Generated/runtime directories such as `dist-newstyle/`, `dist-release/`, `logs/`, `.tmp/`, `tmp/`, `.omx/`, `.pi/`, and `.codex/` are not source.

## Prerequisites

- GHC/Cabal compatible with the package metadata (`tested-with: GHC == 9.14.1`, `cabal-version: 3.14`).
- Native ZeroMQ libraries for the pinned `zmqx` dependency.
- GitHub SSH access for the pinned `cabal.project` dependency `git@github.com:Jacobbishopxy/zmqx.git`, or a local/alternate source override.
- Node/npm for the dashboard.
- mdBook for the documentation build.

## Fast verification

From the repository root:

```bash
cabal update
make ci-check
```

`make ci-check` compiles all components/tests/demos, runs the explicit bounded regression suite list, and builds the mdBook. Useful narrower gates:

```bash
make ci-build        # cabal build all --enable-tests
make ci-test         # bounded regression suites only
make book-build      # mdBook only
make dashboard-build # Vite/TypeScript dashboard build
```

## Run the TaskSchedule cluster locally

Start each long-running role in a separate terminal:

```bash
make dashboard-install                # once, if applications/dashboard/node_modules is absent
make task-schedule-server             # terminal 1: broker + observer API on 127.0.0.1:8081
make task-schedule-worker             # terminal 2: worker connected to broker backend
make task-schedule-client-bridge      # terminal 3: submit bridge on 127.0.0.1:8090/submit
make dashboard-dev                    # terminal 4: dashboard on 127.0.0.1:5173 with proxies
```

Default local topology:

| Component | Default endpoint |
|---|---|
| Broker frontend / clients | `tcp://127.0.0.1:5555` |
| Broker backend / workers | `tcp://127.0.0.1:5556` |
| Worker LogIngest | `tcp://127.0.0.1:5558` |
| Observer API | `http://127.0.0.1:8081/SimpleServer` |
| Client bridge | `http://127.0.0.1:8090/submit` |
| Dashboard dev server | `http://127.0.0.1:5173` |

On a headless Ubuntu server, keep everything bound to loopback and use SSH forwarding from your laptop:

```bash
ssh -L 5173:127.0.0.1:5173 your-user@your-server
```

Then open `http://127.0.0.1:5173` locally.

## Submit tasks

### Dashboard path

Open the dashboard, paste/upload/generate TOML, and click **Submit**. The browser sends only:

```json
{ "format": "toml", "taskToml": "..." }
```

The bridge owns client id, broker frontend address, ACK timeout, body-size limit, and origin policy. It rejects browser-supplied client/worker/broker config. A successful submit response means **accepted/enqueued**, not completed; completion evidence comes later from worker state, logs, task state, or task side effects.

### CLI path

```bash
make task-validate
make task-schedule-submit
make task-submit TASKSCHEDULE_TASK_TOML=tasks/my-task.toml
make task-template TASKSCHEDULE_TASK_TEMPLATE_OUT=tasks/my-task.toml
```

A minimal task is TOML with `schemaVersion = "task-schedule/v2"`, `name`, `[retry]`, `[schedule]`, at least one `[[steps]]`, and optional output/success checks. The checked-in example is `applications/TaskSchedule/config/task-demo.toml`.

## Observe runtime state

Use the dashboard or probe the read-only API directly:

```bash
curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/info
curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/worker_stats
curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/tasks
curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/worker_tasks
curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/logs/stats
```

Deeper operational probes such as `/logs/recent`, `/logs/worker/<workerId>`, `/logs/task/<taskUuid>`, and `/garbage` are documented in the mdBook operations/runbook pages.

## Add workers or move beyond loopback

Default configs bind to loopback. To generate and use public-bind configs for all TaskSchedule TCP binds plus the broker HTTP API and dashboard dev server, set `TASKSCHEDULE_BIND_ALL=1` on the same Make targets:

```bash
TASKSCHEDULE_BIND_ALL=1 TASKSCHEDULE_CONNECT_HOST=<server-ip-or-dns> make task-schedule-server
TASKSCHEDULE_BIND_ALL=1 TASKSCHEDULE_CONNECT_HOST=<server-ip-or-dns> make task-schedule-worker
TASKSCHEDULE_BIND_ALL=1 TASKSCHEDULE_CONNECT_HOST=<server-ip-or-dns> make task-schedule-client-bridge
TASKSCHEDULE_BIND_ALL=1 make dashboard-dev
```

This writes generated configs to `.tmp/task-schedule-bind-all-config/`. `TASKSCHEDULE_BIND_HOST` defaults to `0.0.0.0`; `TASKSCHEDULE_CONNECT_HOST` is the concrete host workers/clients use to reach the broker and should not be `0.0.0.0` for remote machines.

For additional local workers, create another worker JSON with a unique `workerId` and the same broker backend/log addresses, then run:

```bash
make task-schedule-worker TASKSCHEDULE_WORKER_CONFIG=path/to/worker-2.json
```

For multi-host deployments:

1. Prefer `TASKSCHEDULE_BIND_ALL=1 TASKSCHEDULE_CONNECT_HOST=<server-ip-or-dns>` to generate public-bind configs instead of editing checked-in loopback configs.
2. Point remote worker/client/bridge configs at the broker's concrete host or DNS name, not `0.0.0.0`.
3. Keep the dashboard and bridge behind loopback or a same-origin reverse proxy where possible.
4. If exposing the bridge beyond loopback, keep generated `bridgeAllowNoOrigin=false` and enumerate exact `bridgeAllowedOrigins` in the generated or custom bridge config.

The dashboard is an observer-first UI. It intentionally does not expose retry, cancel, delete, worker restart, broker mutation, or scheduler-control actions.

## Smokes and evidence

```bash
make smoke-single              # single worker/server/client smoke
make smoke-multi               # generated multi-worker smoke
make smoke-dashboard-bridge    # broker + worker + bridge + dashboard proxy submit smoke
```

Real browser-click smoke is optional and headless; it needs Chrome/Chromium or `BROWSER_BIN`:

```bash
BROWSER_BIN=/path/to/chrome make smoke-dashboard-browser
```

Smoke evidence is written under ignored `.tmp/` directories.

## Use `lotos` as a library

New applications should import `Lotos.Zmq`, define task and worker-status payloads, and implement the three extension points:

```haskell
class LoadBalancerAlgo lb t w where
  scheduleTasks :: lb -> [(RoutingID, w)] -> [Task t] -> LotosApp (lb, ScheduledResult t w)

class TaskAcceptor ta t where
  processTasks :: TaskAcceptorAPI -> ta -> [Task t] -> LotosApp ta

class StatusReporter sr w where
  gatherStatus :: StatusReporterAPI -> sr -> LotosApp (sr, w)
```

Start with [`docs/build-your-own-scheduler.md`](docs/build-your-own-scheduler.md) and `examples/minimal-scheduler/src/MinimalSchedulerExample.hs`. Use `applications/TaskSchedule/` as the full runtime reference.

Important invariants:

- Preserve `ToZmq`/`FromZmq` multipart frame ordering; it is the wire ABI.
- Compatible protocol changes append payload frames at the tail and keep old-frame decoder tests.
- The broker assigns task UUIDs; worker/scheduler code assumes tasks have UUIDs before execution.
- Client ACKs mean accepted/enqueued, not worker completion.
- Worker liveness is heartbeat-driven; stale workers are removed from scheduling and their non-succeeded in-flight work is recovered through retry/garbage handling.

## Build and release packaging

Targeted builds:

```bash
cabal build lotos
cabal build TaskSchedule:exe:ts-server
cabal build TaskSchedule:exe:ts-worker
cabal build TaskSchedule:exe:ts-client
cabal build TaskSchedule:exe:ts-client-bridge
make task-schedule-build-all
```

Package same-machine TaskSchedule binaries/configs into an ignored release directory:

```bash
make release-clean
make release-task-schedule
```

Output goes to `dist-release/TaskSchedule/` with role binaries, configs, `MANIFEST.txt`, and `SHA256SUMS`.

## Documentation

```bash
make book-build
make book-serve
```

Start here:

- [mdBook start page](docs/book/lotos/src/start-here.md)
- [Dashboard operations manual](docs/book/lotos/src/dashboard-operations.md)
- [Runtime failure runbook](docs/book/lotos/src/runtime-failures.md)
- [Protocol compatibility](docs/book/lotos/src/protocol-compatibility.md)
- [Release readiness](docs/book/lotos/src/release.md)
- [Build your own scheduler](docs/build-your-own-scheduler.md)

Generated mdBook HTML is written to `docs/book/lotos/book/` and should not be committed.

## Development notes

- The workspace uses Cabal, not Stack.
- Both main packages default to `GHC2024`, `OverloadedStrings`, and `-Wall`.
- Prefer component-specific Cabal builds/tests while iterating.
- Do not add no-assertion or long-running demos as Cabal `test-suite` components; use bounded assertion-based tests for regression gates.
