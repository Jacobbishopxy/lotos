# Lotos

Lotos is a Haskell/Cabal workspace for experimenting with a ZeroMQ-backed task load balancer. It contains:

- `lotos`: a reusable library with logging, STM-backed data structures, concurrent process execution, and a ZMQ client/server/worker framework.
- `TaskSchedule`: an example application that schedules shell-command tasks onto workers based on reported CPU and memory load.

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
├── docs/lb_sys.drawio                    # Architecture sketch
├── scripts/                              # Small shell scripts used by demos/tests
├── Makefile                              # Cabal convenience targets
└── hie.yaml                              # Haskell Language Server component map
```

Generated/build/runtime directories such as `dist-newstyle/`, `logs/`, `.tmp/`, `.omx/`, `.pi/`, and `.codex/` are not part of the source tree.

## Packages

### `lotos`

The core library exposes the public API through `Lotos` and `Lotos.Zmq`.

Important modules:

- `Lotos.Logger` — `LotosApp`, logger environment, file/console logger setup, and `forkApp`.
- `Lotos.Proc` / `Lotos.Proc.ConcExecutor` — concurrent shell command execution with callbacks, output streaming, and timeouts.
- `Lotos.TSD.Queue`, `Lotos.TSD.Map`, `Lotos.TSD.RingBuffer` — STM-backed shared data structures.
- `Lotos.Zmq.Adt` — ZMQ multipart serialization classes and message/task/status types.
- `Lotos.Zmq.LBS` — load-balancer server assembly.
- `Lotos.Zmq.LBS.SocketLayer` — frontend/backend router loop and task status handling.
- `Lotos.Zmq.LBS.TaskProcessor` — scheduler trigger loop and `LoadBalancerAlgo` typeclass.
- `Lotos.Zmq.LBS.InfoStorage` — Servant/Warp HTTP state snapshot API.
- `Lotos.Zmq.LBW` — worker service, `TaskAcceptor`, and `StatusReporter` typeclasses.
- `Lotos.Zmq.LBC` — client request service.

### `applications/TaskSchedule`

`TaskSchedule` demonstrates the library with concrete task and worker types:

- `ClientTask`: a shell command plus timeout.
- `WorkerState`: load average, memory usage, and task-count metrics.
- `SimpleServer`: schedules tasks to the least-loaded workers.
- `SimpleWorker`: executes commands with `executeConcurrently` and reports task results.

Executables:

- `TaskSchedule:exe:ts-server` — starts the load balancer and info API.
- `TaskSchedule:exe:ts-worker` — starts one command-executing worker.
- `TaskSchedule:exe:ts-client` — submits a task JSON file to the load balancer frontend and waits for an ACK.

## Architecture overview

At runtime, Lotos uses a broker/worker topology:

1. A client sends a `Task t` to the load balancer frontend.
2. The socket layer assigns a UUID and enqueues the task in an STM queue.
3. The task processor wakes on notifications or a timer, reads worker status, pulls queued and retryable tasks, and calls a user-provided `LoadBalancerAlgo`.
4. Scheduled tasks are forwarded to workers over the backend ZMQ socket.
5. Workers process batches through `TaskAcceptor`, emit per-task status changes, and periodically report worker status through `StatusReporter`.
6. Failed tasks are retried while retry count remains; exhausted tasks move to a garbage ring buffer.
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

## Prerequisites

- GHC 9.14.1 and cabal-install 3.14.2.0 were used for the latest verified build; package files declare `cabal-version: 3.14` and `tested-with: GHC == 9.14.1`.
- ZeroMQ native libraries for the pinned `zmqx` dependency.
- Access to the pinned git dependency in `cabal.project`:

```cabal
source-repository-package
  type: git
  location: git@github.com:Jacobbishopxy/zmqx.git
  tag: d476d1c6c4713b192626ea1c7e6b830c4860ed8c
```

Fresh environments need GitHub SSH access or a local/alternate source override for `zmqx`.

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
```

## Tests and demos

Use a CI-safe test posture: registered Cabal test suites are bounded, assertion-based regressions; demo and server examples are Cabal executables that must be run intentionally.

| Goal | Command | Notes |
|---|---|---|
| Full regression | `cabal test all` | Runs the bounded `lotos` regression suites only: `test-conc-executor`, `test-zmq-worker-frames`, and `test-zmq-client-ack-frames`. |
| Focused quick regression | `cabal test lotos:test:test-conc-executor` | HUnit coverage for concurrent command success/failure, callbacks, timeout handling, and bounded concurrent execution. |
| Compile all packages, tests, and demos | `cabal build all --enable-tests` | Builds the workspace, regression test executables, TaskSchedule executables, and `demo-*` executables without running long-lived demos. |
| Intentional MVP smoke | `scripts/task-schedule-smoke.sh` | Bounded server/worker/client smoke; run after the build command above and inspect `.tmp/task-schedule-smoke/<run-id>/` for `result.env`, logs, endpoint snapshots, and marker proof. |

Current `lotos` regression test suites:

- `test-conc-executor` is the concurrent process executor regression suite.
- `test-zmq-worker-frames` checks bounded worker-status ROUTER/DEALER frame decoding.
- `test-zmq-client-ack-frames` checks bounded frontend REQ/ROUTER client ACK frames.

Current `lotos` demo executables:

- `demo-conc-executor2` is a bounded concurrent executor demo with helper scripts and no assertions; run it from the repository root so `scripts/*` and `.tmp/*` paths resolve consistently (`cabal run lotos:exe:demo-conc-executor2`).
- `demo-event-trigger` is a bounded timing demo with sleeps and no assertions (`cabal run lotos:exe:demo-event-trigger`).
- `demo-logger` is a long-running logging demo that sleeps for roughly 50 seconds (`timeout 70s cabal run lotos:exe:demo-logger`).
- `demo-simple-servant` starts a Warp server on port 8080 and does not exit by itself (`timeout 15s cabal run lotos:exe:demo-simple-servant`).
- `demo-zmq-xt` starts long-running ZMQ loops and does not exit by itself (`timeout 15s cabal run lotos:exe:demo-zmq-xt`).

Do not add no-assertion demos back as Cabal `test-suite` components unless they are bounded and assertion-based; otherwise `cabal test all` stops being a safe regression gate.

## Running the TaskSchedule demo

The MVP runtime contract for the server, worker, client, task JSON, and verification flow is documented in [`docs/task-schedule-mvp.md`](docs/task-schedule-mvp.md).

The executables use built-in single-machine defaults and can also read explicit JSON config files. Sample configs live under `applications/TaskSchedule/config/`.

Default addresses:

- server frontend / client frontend: `tcp://127.0.0.1:5555`
- server backend / worker task-status backend: `tcp://127.0.0.1:5556`
- reserved worker logging endpoint: `tcp://127.0.0.1:5557`
- info HTTP port: `8081`
- logs: `./logs/taskScheduleServer.log`, `./logs/taskScheduleWorker.log`, and `./logs/taskScheduleClient.log`

Start the server with defaults, or pass `applications/TaskSchedule/config/broker.json` to make the defaults explicit:

```bash
cabal run TaskSchedule:exe:ts-server
cabal run TaskSchedule:exe:ts-server -- applications/TaskSchedule/config/broker.json
```

Start a worker in another terminal with defaults, or pass `applications/TaskSchedule/config/worker.json`:

```bash
cabal run TaskSchedule:exe:ts-worker
cabal run TaskSchedule:exe:ts-worker -- applications/TaskSchedule/config/worker.json
```

Submit a task JSON with the client. A client config can be supplied as the first argument when overriding the frontend address or timeout:

```bash
cabal run TaskSchedule:exe:ts-client -- task-demo.json
cabal run TaskSchedule:exe:ts-client -- applications/TaskSchedule/config/client.json task-demo.json
```

For a repeatable local smoke run, compile all packages and test targets first, then run the helper from the repository root:

```bash
cabal build all --enable-tests
scripts/task-schedule-smoke.sh
```

The smoke helper starts the server and worker with the checked-in sample configs, submits a fresh per-run task when worker readiness passes, captures evidence under `.tmp/task-schedule-smoke/<run-id>/`, and cleans up only the processes it started. Exit `0` means the full MVP path passed: client ACK, worker stats, fresh marker proof, and no current-run garbage entry. Exit `1` means a runtime, readiness, ACK, marker, or garbage check failed; inspect the evidence directory for `result.env`, `smoke.log`, stdio logs, endpoint snapshots, and the marker file.

Latest TP-009 evidence `.tmp/task-schedule-smoke/tp009-final-20260601T043107Z-241489/` is green with `status=PASS`, `client_exit=0`, `accepted/enqueued ACK`, worker `simpleWorker_1` in stats, fresh marker proof, and no current-run garbage entry.

## Info API

`runLBS @"SimpleServer"` serves a Servant API under the load-balancer name. With the demo server, useful endpoints include:

- `http://127.0.0.1:8081/SimpleServer/info`
- `http://127.0.0.1:8081/SimpleServer/tasks`
- `http://127.0.0.1:8081/SimpleServer/garbage`
- `http://127.0.0.1:8081/SimpleServer/worker_tasks`
- `http://127.0.0.1:8081/SimpleServer/worker_stats`

## Development notes

- The workspace uses Cabal, not Stack.
- Both packages default to `GHC2024`, `OverloadedStrings`, and `-Wall`.
- Preserve `ToZmq`/`FromZmq` multipart frame ordering when editing protocol types; the peer side depends on exact frame order.
- `Task` values should have UUIDs before scheduling or worker execution; code paths using `unsafeGetTaskID` assume this invariant.
- Prefer component-specific builds/tests while some test suites are demos or long-running processes.
