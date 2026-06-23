# Lotos

Lotos is a Haskell/Cabal workspace for experimenting with a ZeroMQ-backed task load balancer. It contains:

- `lotos`: a reusable library with logging, STM-backed data structures, concurrent process execution, and a ZMQ client/server/worker framework.
- `TaskSchedule`: an example application that schedules shell-command tasks onto workers based on reported CPU and memory load.
- `applications/dashboard`: a Vite + TypeScript dashboard for a light live runtime overview with sample/offline fallback and an optional submit-only TOML bridge panel.

## Repository layout

```text
.
├── cabal.project                         # Cabal workspace definition
├── lotos/                                # Core library package
│   ├── lotos.cabal
│   ├── src/Lotos.hs
│   ├── src/Lotos/Logger.hs               # ReaderT logging environment and helpers
│   ├── src/Lotos/Proc.hs                 # Concurrent shell command execution API
│   ├── src/Lotos/TSD/                    # STM queue/map/ring-buffer helpers
│   └── src/Lotos/Zmq/                    # Load-balancer server, worker, client, ADTs
├── applications/TaskSchedule/            # Example command-scheduling app
│   ├── TaskSchedule.cabal
│   ├── app/                              # ts-server, ts-worker, ts-client entry points
│   └── src/                              # scheduler, worker, client task types
├── applications/dashboard/               # Light live-data dashboard (Vite + TypeScript)
├── examples/minimal-scheduler/           # Tiny public-API-only scheduler package
├── docs/lb_sys.drawio                    # Architecture sketch
├── docs/book/lotos/                      # mdBook architecture/API/runbook docs
├── docs/task-schedule-mvp.md             # TaskSchedule runtime contract and smoke evidence
├── docs/build-your-own-scheduler.md      # Concise guide for new library adopters
├── scripts/                              # Small shell scripts used by demos/tests
├── Makefile                              # Cabal convenience targets
└── hie.yaml                              # Haskell Language Server component map
```

Generated/build/runtime directories such as `dist-newstyle/`, `logs/`, `.tmp/`, `.omx/`, `.pi/`, and `.codex/` are not part of the source tree.

## Packages

### `lotos`

The core library exposes the public API through `Lotos` and `Lotos.Zmq`.

Important public modules:

- `Lotos.Logger` — `LotosApp`, logger environment, file/console logger setup, and `forkApp`.
- `Lotos.Proc` — concurrent shell command execution with callbacks, output streaming, and timeouts.
- `Lotos.TSD.Queue`, `Lotos.TSD.Map`, `Lotos.TSD.RingBuffer` — STM-backed shared data structures.
- `Lotos.Zmq` — the supported facade for ZMQ config/readers, protocol types, client/server/worker entry points, and the `LoadBalancerAlgo`, `TaskAcceptor`, and `StatusReporter` extension points.

Lower-level `Lotos.Zmq.*` implementation modules are intentionally not part of the public API. The exposed internal ZMQ modules are limited to `Lotos.Zmq.Internal.Retry` and `Lotos.Zmq.Internal.Liveness`, which exist for bounded broker regression tests and retry/liveness implementation work; normal applications should prefer `Lotos.Zmq`.

### `applications/TaskSchedule`

`TaskSchedule` demonstrates the library with concrete task and worker types:

- `ClientTask`: a TOML-authored task contract with inputs, shell steps, outputs, and success checks.
- `WorkerState`: load average, device CPU percentage, memory usage, task-count metrics, and configured task capacity.
- `SimpleServer`: schedules by remaining worker capacity, preferring the least-loaded workers and leaving overflow queued when no capacity remains.
- `SimpleWorker`: validates task contracts, executes shell steps, checks outputs/proofs, and reports task results.

Executables:

- `TaskSchedule:exe:ts-server` — starts the load balancer and info API.
- `TaskSchedule:exe:ts-worker` — starts one command-executing worker.
- `TaskSchedule:exe:ts-client` — submits a task TOML file to the load balancer frontend and waits for an ACK.
- `TaskSchedule:exe:ts-client-bridge` — local HTTP bridge for dashboard submit-only TOML envelopes; it owns client/ZMQ config server-side and reuses the `ts-client` ACK path.

### `applications/dashboard`

The dashboard is a Vite + TypeScript app under [`applications/dashboard/`](applications/dashboard/). It polls the TaskSchedule observer API (`/SimpleServer/info`, `/worker_stats`, `/worker_tasks`, `/tasks`, and `/logs/stats`) when available, keeps rendering useful sample/offline data when the backend is stopped, and can optionally submit TOML through a local client bridge. The submit panel supports paste/edit, file import, and a minimal generated-template form, but sends only `{ format: "toml", taskToml: "..." }`; the bridge owns client id, frontend address, and ACK timeout and reuses the existing ZMQ client request path. The visual direction is light and Linear-inspired: near-white canvas, quiet gray hierarchy, hairline borders, restrained cards, and one lavender-blue primary accent.

For the shortest live local path, start the TaskSchedule roles with root Make targets, then open the dashboard dev server. Run the long-lived server, worker, bridge, and dashboard commands in separate terminals:

```bash
make dashboard-install                # once, if node_modules is absent
make task-schedule-server             # terminal 1; info API on http://127.0.0.1:8081
make task-schedule-worker             # terminal 2; connects to the broker backend
make task-schedule-client-bridge      # terminal 3; local submit bridge on http://127.0.0.1:8090/submit
make dashboard-dev                    # terminal 4; serves on 127.0.0.1 and proxies /SimpleServer plus /submit
# optional CLI paths remain available:
make task-schedule-submit             # submit the demo task without the dashboard
make task-validate                    # validate task TOML without submitting
```

The full [Dashboard Operations Manual](docs/book/lotos/src/dashboard-operations.md) documents startup order, role boundaries, observer endpoints, the optional submit-only bridge, overrides, troubleshooting, and manual browser verification. Use the root Make targets to install dependencies, build, develop, preview, or smoke the app:

```bash
make dashboard-install
make dashboard-build                  # no live server required; sample/offline fallback remains available
make dashboard-dev                    # serves on DASHBOARD_HOST and proxies /SimpleServer plus /submit
make smoke-dashboard-bridge           # server + worker + bridge + dashboard proxy submit evidence under .tmp/
make smoke-dashboard-browser          # same smoke plus real browser click automation; requires BROWSER_BIN or Chrome/Chromium on PATH
DASHBOARD_HOST=127.0.0.1 DASHBOARD_API_TARGET=http://127.0.0.1:8081 DASHBOARD_BRIDGE_TARGET=http://127.0.0.1:8090 make dashboard-dev
DASHBOARD_API_BASE=http://127.0.0.1:8081 DASHBOARD_BRIDGE_BASE=http://127.0.0.1:8090 make dashboard-build  # direct bases are baked at build time and require same-origin/external CORS proxying
make dashboard-preview
```

### `examples/minimal-scheduler`

`lotos-minimal-scheduler-example` is a deliberately small external-style package. It imports the public `Lotos.Zmq` facade, defines one task payload and one worker-status payload, adds a tiny `sendTaskRequest` client helper, implements `LoadBalancerAlgo`, `TaskAcceptor`, and `StatusReporter`, and ships a bounded HUnit fixture plus `make example-minimal` assignment preview. It does not import TaskSchedule or lower-level implementation modules, so it is the quickest proof that a first user can build a custom scheduler from the public API alone.

## Quickstart for new adopters

From a checkout with GHC/Cabal, mdBook, and ZeroMQ available:

```bash
cabal update
make ci-check
```

`make ci-check` is the routine TP-049 gate: it compiles every workspace component with tests enabled, runs the explicit bounded regression target list, and builds the mdBook. Use the narrower targets when iterating locally:

```bash
make ci-build        # cabal build all --enable-tests
make ci-test         # explicit bounded regression suites only
make book-build      # mdBook only
make dashboard-build # dashboard Vite build with offline fallback
```

Then run one of the intentional end-to-end demo smokes from the repository root after the build/test gate is green:

```bash
make smoke-single  # or scripts/task-schedule-smoke.sh
make smoke-multi   # or scripts/task-schedule-multi-worker-smoke.sh
```

For a manual single-machine demo, start the server and worker in separate terminals, then submit the checked-in sample task from a third terminal. The checked-in JSON config files make the default loopback topology explicit: `broker.json` owns the frontend/backend/LogIngest/info endpoints, `worker.json` points at the backend plus worker logging endpoint, `client.json` points at the frontend and ACK timeout, and `task-demo.toml` is the submitted task contract.

```bash
mkdir -p logs .tmp

# Terminal 1
make task-schedule-server

# Terminal 2
make task-schedule-worker

# Terminal 3
make task-schedule-submit
sleep 5
cat .tmp/task-schedule-demo.out
```

The client ACK means the broker accepted/enqueued the task; completion proof comes from the worker marker file, worker logs, or the info API. Client request submission remains a direct synchronous REQ/ACK exchange, and `ClientServiceConfig.reqTimeoutSec` bounds how long `sendTaskRequest` waits for that ACK before returning `Nothing`.

Useful manual probes while the demo is running:

```bash
curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/info | jq '.workerLivenessMap'
curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/info | jq '.workerReservationMap'
curl --noproxy '*' -fsS http://127.0.0.1:8081/SimpleServer/info | jq '.runtimeQueueStats[] | {name,currentDepth,overloadStatus}'
```

To build a new scheduler on top of `lotos`, start with [`docs/build-your-own-scheduler.md`](docs/build-your-own-scheduler.md), skim `examples/minimal-scheduler/src/MinimalSchedulerExample.hs` for the smallest public-API-only implementation, then use the TaskSchedule source files as the full runtime reference implementation.

## Architecture and API book

A lightweight mdBook collects the architecture observations, public API guide, ZMQ/EventLoop ownership notes, TaskSchedule runbook, runtime failure runbook, compatibility notes, release-readiness policy, and verification checklist without duplicating all details in this README:

```bash
make book-build
make book-serve
# optional overrides
make book-serve MDBOOK_HOST=0.0.0.0 MDBOOK_PORT=3004 MDBOOK_DIR=docs/book/lotos
```

The book source is under [`docs/book/lotos`](docs/book/lotos/src/SUMMARY.md). New readers should start with [Start Here](docs/book/lotos/src/start-here.md). Use the [Dashboard Operations Manual](docs/book/lotos/src/dashboard-operations.md) for the observer plus optional submit-only dashboard path and the [Runtime Failure Runbook](docs/book/lotos/src/runtime-failures.md) when diagnosing stuck workers, LogIngest backlog, broker overload, stale heartbeats, capacity-reservation surprises, or smoke failures. Generated HTML is written to `docs/book/lotos/book/` by mdBook and should not be committed.

## Architecture overview

At runtime, Lotos uses a broker/worker topology:

1. A client sends a `Task t` to the load balancer frontend.
2. The socket layer assigns a UUID and enqueues the task in an STM queue.
3. The task processor wakes on notifications or a timer, removes workers whose latest status heartbeat is older than `taskProcessor.workerStaleTimeoutSec`, pulls queued and retryable tasks, and calls a user-provided `LoadBalancerAlgo` with only non-stale worker snapshots.
4. Scheduled tasks are forwarded to workers over the backend ZMQ socket.
5. Workers process batches through `TaskAcceptor`, emit per-task status changes, and periodically report worker status through `StatusReporter`.
6. Failed tasks, including in-flight tasks recovered from stale workers, are retried while retry count remains after any positive `taskRetryInterval` delay has elapsed; exhausted tasks move to a garbage ring buffer.
7. Info storage snapshots queues, worker state, worker-task state, and garbage tasks for a read-only HTTP API.

The main extension points are:

```haskell
class LoadBalancerAlgo lb t w where
  scheduleTasks :: lb -> [(RoutingID, w)] -> [Task t] -> LotosApp (lb, ScheduledResult t w)

class TaskAcceptor ta t where
  processTasks :: TaskAcceptorAPI -> ta -> [Task t] -> LotosApp ta

class StatusReporter sr w where
  gatherStatus :: StatusReporterAPI -> sr -> LotosApp (sr, w)
```

## Using `lotos` as a library

For a new application, import `Lotos.Zmq` and provide application payloads plus the three extension points above:

1. Define a task payload and worker-status payload with `ToZmq`/`FromZmq` instances. Their multipart frame order is the protocol contract; keep peer encoders/decoders and regression tests aligned. Compatible wire changes are append-only at the payload tail and must keep old-frame decoder coverage.
2. Define a `Task t` JSON shape for clients. New client tasks may leave `taskID = null`; the broker assigns the UUID before scheduling, and worker/scheduler code assumes a UUID is present before calling `unsafeGetTaskID`. `taskRetryInterval` is a retry delay in seconds for failed tasks with retries remaining; `0` or less retries immediately.
3. Implement `LoadBalancerAlgo` for the server. `scheduleTasks` receives current non-stale worker snapshots and a bounded batch of queued/retryable tasks; return `ScheduledResult` assignments plus any tasks to leave queued for a later pass. If your worker status models capacity, implement the optional `applyCapacityReservations` and `workerOccupiedSlots` hooks so the broker can overlay dispatch reservations between heartbeats without exposing internal maps. The TaskSchedule demo reports configured worker capacity in `WorkerState.taskCapacity`, overlays reservations onto waiting work, subtracts reported processing/waiting work, assigns fresh tasks across remaining slots in load-sorted rounds, and leaves overflow queued.
4. Implement `TaskAcceptor` for workers. Process each task batch, enqueue structured task logs with `taSendTaskLog` (or the compatibility `taPubTaskLogging` wrapper), and report `TaskProcessing`, `TaskSucceed`, or `TaskFailed` with `taSendTaskStatus`.
5. Implement `StatusReporter` for workers. Combine `StatusReporterAPI.srReportInfo` queue/processing counts with app-specific metrics such as CPU or memory load.
6. Keep config endpoints aligned: clients use the broker `frontendAddr`, workers use the broker `backendAddr`, and worker log DEALER sockets connect to the broker `logIngest.logIngestAddr` / worker `workerLogging.logIngestAddr`. New JSON should prefer `infoStorage.logIngestDefaultAddr` / `logIngestDefaultBufferSize` only as broker derivation hints and explicit `workerLogging.logIngestAddr` for workers; legacy `infoStorage.loggingAddr`, `infoStorage.loggingsBufferSize`, and `loadBalancerLoggingAddr` remain accepted for old JSON/default derivation. The current reliable logging design is documented in [`docs/logging-redesign.md`](docs/logging-redesign.md).

Concrete examples live at two sizes. `examples/minimal-scheduler/src/MinimalSchedulerExample.hs` is the smallest public-API-only fixture for a custom scheduler, client submission helper, acceptor, and status reporter; run `make example-minimal` for a bounded assignment preview. The TaskSchedule demo is the full runtime example: `applications/TaskSchedule/src/Adt.hs` defines task/status payload frames, `applications/TaskSchedule/src/Server.hs` implements `LoadBalancerAlgo`, and `applications/TaskSchedule/src/Worker.hs` implements both worker typeclasses. The concise adopter checklist is [`docs/build-your-own-scheduler.md`](docs/build-your-own-scheduler.md); the full demo runtime contract and smoke path remain in [`docs/task-schedule-mvp.md`](docs/task-schedule-mvp.md).

## Prerequisites

- GHC 9.14.1 and cabal-install 3.16.1.0 were used for the latest verified build; package files declare `cabal-version: 3.14` and `tested-with: GHC == 9.14.1`.
- ZeroMQ native libraries for the pinned `zmqx` dependency.
- Access to the pinned git dependency in `cabal.project`:

```cabal
source-repository-package
  type: git
  location: git@github.com:Jacobbishopxy/zmqx.git
  tag: v0.1.1.1
```

Fresh environments need GitHub SSH access or a local/alternate source override for `zmqx`. The package `.cabal` files carry conservative PVP-style upper bounds for public-library dependencies; the `cabal.project` `source-repository-package`, `allow-newer`, and setup constraints are workspace development overrides rather than published package policy. The current GHC 9.14.1 workspace plan relies on `allow-newer` because upstream `servant-server` metadata excludes `base-4.22`, so public packaging still needs a strict solver profile. See the mdBook [Release Readiness](docs/book/lotos/src/release.md) page for the current first-release metadata policy and known non-release gaps.

## Build

```bash
cabal update
cabal build all
# or
make build
```

Targeted builds:

```bash
cabal build lotos
cabal build TaskSchedule:exe:ts-server
cabal build TaskSchedule:exe:ts-worker
cabal build TaskSchedule:exe:ts-client
make task-schedule-build-all
```

## TaskSchedule release packaging

For same-machine production packaging after cloning/building on the target OS, use:

```bash
make release-clean
make release-task-schedule
```

This writes an ignored release bundle under `dist-release/TaskSchedule/`:

```text
bin/ts-server
bin/ts-worker
bin/ts-client
config/broker.json
config/worker.json
config/client.json
tasks/task-demo.toml
MANIFEST.txt
SHA256SUMS
```

Role-specific packaging is also available with `make release-server`, `make release-worker`, and `make release-client`.

## Tests and demos

Use a CI-safe test posture: registered Cabal test suites are bounded, assertion-based regressions; demo and server examples are Cabal executables that must be run intentionally.

| Goal | Command | Notes |
|---|---|---|
| Routine CI/local gate | `make ci-check` | Runs `ci-build`, `ci-test`, and `ci-docs`: compile every workspace component/test/demo executable, run the explicit bounded regression target list, and build the mdBook. |
| Compile all packages, tests, and demos | `make ci-build` | Executes `cabal build all --enable-tests`; this compiles demo executables without running long-lived demos. |
| Full bounded regression | `make ci-test` | Runs the explicit test target list in `CI_TEST_TARGETS`; this avoids relying on unbounded demo/server executables. Override `CI_TEST_TARGETS=...` for a narrower local pass. |
| Documentation gate | `make ci-docs` or `make book-build` | Builds the mdBook from `docs/book/lotos` without committing generated `book/` output. |
| Focused quick regression | `cabal test lotos:test:test-conc-executor` | HUnit coverage for concurrent command success/failure, callbacks, timeout handling, and bounded concurrent execution. |
| Intentional single-worker MVP smoke | `make smoke-single` or `scripts/task-schedule-smoke.sh` | Bounded server/worker/client smoke; run after `make ci-build` and inspect `.tmp/task-schedule-smoke/<run-id>/` for `result.env`, logs, marker proof, `/info.runtimeQueueStats`, LogIngest-only `/logs/stats`, and endpoint snapshots. |
| Intentional multi-worker smoke | `make smoke-multi` or `scripts/task-schedule-multi-worker-smoke.sh` | Starts one server, at least two generated worker configs, and multiple distinct clients/tasks; inspect `.tmp/task-schedule-multi-worker-smoke/<run-id>/` for LogIngest journal evidence, capacity/reservation snapshots, markers, runtime/log stats, endpoint snapshots, and `result.env`. |

Current bounded regression test suites:

- `lotos:test:test-conc-executor` is the concurrent process executor regression suite.
- `lotos:test:test-zmq-worker-frames` checks bounded worker status, worker task-status, retry/failure status payload, retry-delay eligibility, stale-worker recovery, and scheduled task ROUTER/DEALER frame contracts.
- `lotos:test:test-zmq-client-ack-frames` checks bounded frontend REQ/ROUTER client ACK frames and the client-service ACK timeout path.
- `lotos:test:test-zmq-log-protocol-config` checks reliable log protocol frames plus old/new/mixed JSON config compatibility defaults and checked-in TaskSchedule config parsing.
- `lotos:test:test-zmq-log-ingest` checks broker LogIngest cache, journal, query/stats, ACK, rejection, and same-address startup behavior.
- `lotos:test:test-zmq-worker-log-transport` checks worker-side bounded buffering, drop markers, ACK retry clearing, and wire-rounded ACK matching.
- `TaskSchedule:test:test-worker-lifecycle` checks TaskSchedule command-result status/log mapping and worker lifecycle callbacks.
- `TaskSchedule:test:test-scheduler` checks SimpleServer multi-worker fairness, derived backpressure, all-saturated deferral, and least-loaded worker preference.
- `lotos-minimal-scheduler-example:test:test-minimal-scheduler-example` checks the external minimal scheduler package's payload frames, capacity/reservation hooks, and assignment/deferred-task behavior.

Current `lotos` demo executables:

- `demo-conc-executor2` is a bounded concurrent executor demo with helper scripts and no assertions; run it from the repository root so `scripts/*` and `.tmp/*` paths resolve consistently (`cabal run lotos:exe:demo-conc-executor2`).
- `demo-event-trigger` is a bounded timing demo with sleeps and no assertions (`cabal run lotos:exe:demo-event-trigger`).
- `demo-logger` is a long-running logging demo that sleeps for roughly 50 seconds (`timeout 70s cabal run lotos:exe:demo-logger`).
- `demo-simple-servant` starts a Warp server on port 8080 and does not exit by itself (`timeout 15s cabal run lotos:exe:demo-simple-servant`).
- `demo-zmq-xt` starts long-running ZMQ loops and does not exit by itself (`timeout 15s cabal run lotos:exe:demo-zmq-xt`).

Do not add no-assertion demos back as Cabal `test-suite` components unless they are bounded and assertion-based; otherwise `cabal test all` stops being a safe regression gate.

## Running the TaskSchedule demo

The MVP runtime contract for the server, worker, client, task TOML, and verification flow is documented in [`docs/task-schedule-mvp.md`](docs/task-schedule-mvp.md).

The executables use built-in single-machine defaults and can also read explicit JSON config files. Sample configs and the copyable TOML task contract live under `applications/TaskSchedule/config/`.

Default addresses:

- server frontend / client frontend: `tcp://127.0.0.1:5555`
- server backend / worker task-status backend: `tcp://127.0.0.1:5556`
- logging compatibility/default-derivation endpoint (`infoStorage.logIngestDefaultAddr`; legacy `infoStorage.loggingAddr` / `loadBalancerLoggingAddr` still accepted): `tcp://127.0.0.1:5557`
- reliable worker log ingest endpoint (broker LogIngest ROUTER / worker Log DEALER): `tcp://127.0.0.1:5558`
- info HTTP port: `8081`
- logs: `./logs/taskScheduleServer.log`, `./logs/taskScheduleWorker.log`, and `./logs/taskScheduleClient.log`
- worker stale timeout: `taskProcessor.workerStaleTimeoutSec = 60` seconds in the checked-in broker config; keep it above `workerStatusReportIntervalSec` for healthy workers.
- worker tags: `workerTags` in worker JSON reports operator-defined capabilities/locations such as `linux`, `gpu`, or `site-a`; TaskSchedule routes tasks only to workers satisfying `[schedule].requiredTags` and prefers workers matching `[schedule].preferredTags` when compatible slots are available.

Start the server with defaults, or use the root Make target to pass `applications/TaskSchedule/config/broker.json` explicitly:

```bash
cabal run TaskSchedule:exe:ts-server
make task-schedule-server
```

Start a worker in another terminal with defaults, or use the root Make target to pass `applications/TaskSchedule/config/worker.json`:

```bash
cabal run TaskSchedule:exe:ts-worker
make task-schedule-worker
```

Submit a task TOML contract with the client. A client config can be supplied as the first argument when overriding the frontend address or `reqTimeoutSec`; if no ACK arrives before that timeout, `ts-client` exits non-zero with a no-ACK message. The root Make target passes the checked-in client config and sample task:

```bash
cabal run TaskSchedule:exe:ts-client -- applications/TaskSchedule/config/task-demo.toml
make task-schedule-submit
make task-submit TASKSCHEDULE_TASK_TOML=tasks/my-task.toml
make task-validate TASKSCHEDULE_TASK_TOML=tasks/my-task.toml
make task-template TASKSCHEDULE_TASK_TEMPLATE_OUT=tasks/new-task.toml
```

For repeatable local smoke runs, compile all packages and test targets first, then run the desired helper from the repository root:

```bash
cabal build all --enable-tests
scripts/task-schedule-smoke.sh
scripts/task-schedule-multi-worker-smoke.sh
```

The single-worker smoke helper starts the server and one worker with the checked-in sample configs, submits a fresh per-run task when worker readiness passes, captures evidence under `.tmp/task-schedule-smoke/<run-id>/`, and cleans up only the processes it started. Exit `0` means the full MVP path passed: client ACK, worker stats, fresh marker proof, current-run worker logging in `/SimpleServer/logs/worker/simpleWorker_1` plus clean `/SimpleServer/logs/stats`, and no current-run garbage entry. Exit `1` means a runtime, readiness, ACK, marker, worker-logging, or garbage check failed; inspect the evidence directory for `result.env`, `smoke.log`, stdio logs, endpoint snapshots, and the marker file.

The multi-worker smoke helper generates a per-run broker config, two worker configs by default (`smokeWorker_1` and `smokeWorker_2`), unique client configs, and four fresh task TOML files. It requires all workers to appear in `/SimpleServer/worker_stats`, all clients to receive ACKs, every task marker to match the current run, LogIngest journal evidence for every worker, `/SimpleServer/logs/worker/<workerId>` to contain current-run stdout plus final `ExitSuccess` result events for each worker, clean `/SimpleServer/logs/stats`, no current-run garbage, and no leftover `ts-server`/`ts-worker`/`ts-client` processes from its tracked process groups.

Latest TP-049 verification profile is green: `make ci-check` compiles all components with tests enabled, runs the explicit bounded regression target list, and builds the mdBook. Intentional single- and multi-worker smokes remain opt-in after the build gate. The bounded scheduler suite covers deterministic assignment/deferred-task behavior, while the smoke helpers prove end-to-end execution and reliable `/logs` evidence without relying on timing-sensitive exact distribution.

## Info API

`runLBS @"SimpleServer"` serves a Servant API under the load-balancer name. With the demo server, useful endpoints include:

- `http://127.0.0.1:8081/SimpleServer/info`
- `http://127.0.0.1:8081/SimpleServer/tasks`
- `http://127.0.0.1:8081/SimpleServer/garbage`
- `http://127.0.0.1:8081/SimpleServer/worker_tasks`
- `http://127.0.0.1:8081/SimpleServer/worker_stats`
- `http://127.0.0.1:8081/SimpleServer/logs/recent`
- `http://127.0.0.1:8081/SimpleServer/logs/worker/<workerId>`
- `http://127.0.0.1:8081/SimpleServer/logs/task/<taskUuid>`
- `http://127.0.0.1:8081/SimpleServer/logs/stats`

The `/info` response is intentionally a lightweight scheduler snapshot; worker log payloads are served through the `/logs/*` LogIngest routes instead. With the checked-in sample configs, workers send command stdout/stderr and final `CommandResult` entries over the reliable `5558` LogIngest endpoint. Query responses have `{ "count": number, "events": [...] }`; `/logs/stats` reports accepted events, duplicate retries, sequence gaps, visible dropped spans, rejected records, worker/task cache cardinality, and accepted-through watermarks. Log delivery is at-least-once with broker-side deduplication, bounded worker/read-cache memory, and explicit drop/gap visibility; exactly-once delivery is not claimed. See [`docs/logging-redesign.md`](docs/logging-redesign.md).

## Protocol and verification invariants

- `ToZmq` and `FromZmq` instances define positional multipart wire formats. Treat them as a stable wire ABI: compatible changes append payload frames at the tail, keep old-frame decoder fallbacks, and update bounded frame tests; route/envelope/discriminator changes require an explicit protocol migration using a new discriminator, endpoint, or versioned payload. The mdBook [Protocol Compatibility and Versioning](docs/book/lotos/src/protocol-compatibility.md#versioning-decision-matrix) chapter has the full decision matrix and break/version-tag policy.
- Client ACKs mean accepted/enqueued by the broker, not worker completion. Completion evidence comes from worker side effects, worker task/status state, logs, or smoke artifacts.
- The broker owns UUID assignment. Client task TOML omits `taskID`; the client builds a new request and the broker assigns the UUID before scheduling/execution.
- Worker DEALER routing ids and reliable worker log DEALER routing ids both use `workerId`; custom configs must align client/frontend, worker/backend, and LogIngest endpoints.
- Failed tasks retry while `taskRetry > 0`; positive `taskRetryInterval` values delay eligibility until the interval has elapsed, while `0` or less preserves immediate retry.
- Worker status heartbeats drive broker liveness. When a worker is stale for `taskProcessor.workerStaleTimeoutSec`, the broker removes it from scheduling/info maps and recovers its non-succeeded in-flight tasks through the same retry/garbage path.
- TaskSchedule's demo scheduler uses `WorkerState.taskCapacity - processingTaskNum - waitingTaskNum` as remaining capacity, filters by required task/worker tags, prefers matching preferred tags, and otherwise prefers lower `cpuUsagePercent`/memory workers. The capacity, device-CPU, and worker-tag fields are append-only worker-status payload fields; decoders still accept older payload shapes as conservative single-slot/unknown-CPU/untagged worker statuses. See the mdBook protocol compatibility chapter for append-only examples and break criteria.
- Safe verification commands are `make ci-check` for the routine compile/test/docs gate, `make ci-test` for the explicit bounded regression list, `make smoke-single` / `scripts/task-schedule-smoke.sh` for the intentional single-worker end-to-end demo smoke, and `make smoke-multi` / `scripts/task-schedule-multi-worker-smoke.sh` for bounded multi-worker scheduling smoke after building.

## Development notes

- The workspace uses Cabal, not Stack.
- Both packages default to `GHC2024`, `OverloadedStrings`, and `-Wall`.
- Preserve `ToZmq`/`FromZmq` multipart frame ordering when editing protocol types; the peer side depends on exact frame order.
- `Task` values should have UUIDs before scheduling or worker execution; code paths using `unsafeGetTaskID` assume this invariant.
- Prefer component-specific builds/tests while some test suites are demos or long-running processes.
