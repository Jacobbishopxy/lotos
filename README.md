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
- `TaskSchedule:exe:ts-client` — currently a placeholder that prints `whatever`.

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

The most suitable quick regression test is the concurrent executor suite:

```bash
cabal test lotos:test:test-conc-executor
```

Be careful with broad test commands:

- `test-simple-servant` starts a web server and does not exit by itself.
- `test-zmq-xt` is a long-running ZMQ demo.
- `test-logger` sleeps for roughly 50 seconds.
- `test-event-trigger` is a short demo-style executable for trigger timing behavior.

For that reason, avoid `cabal test all` as a default verification command until the demo suites are separated from long-running processes.

## Running the TaskSchedule demo

The MVP runtime contract for the server, worker, client, task JSON, and verification flow is documented in [`docs/task-schedule-mvp.md`](docs/task-schedule-mvp.md).

The server executable currently hardcodes these settings:

- frontend: `tcp://127.0.0.1:5555`
- backend: `tcp://127.0.0.1:5556`
- info HTTP port: `8081`
- log file: `./logs/taskScheduleServer.log`

Start it with:

```bash
mkdir -p logs
cabal run TaskSchedule:exe:ts-server
```

Start a worker in another terminal:

```bash
mkdir -p logs
cabal run TaskSchedule:exe:ts-worker
```

Note: the worker executable currently has hardcoded addresses that look inverted relative to the server (`loadBalancerBackendAddr = tcp://127.0.0.1:5555`, `loadBalancerLoggingAddr = tcp://127.0.0.1:5556`). Verify and adjust these before relying on the demo operationally.

The client executable is still a stub. The reusable `Client` module can read a JSON `ClientTask`, but the CLI path has not been completed.

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
