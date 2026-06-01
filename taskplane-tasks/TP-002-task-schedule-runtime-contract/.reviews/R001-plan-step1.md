## Plan Review: Step 1: Define the contract

### Verdict: REVISE

### Summary
The proposal targets the right artifact and covers most user-facing surfaces: server/worker/client startup, defaults, task submission, and info endpoints. Before it becomes the downstream source of truth, it needs to turn a couple of ambiguous runtime decisions into explicit contract choices, especially logging/observability and timeout semantics.

### Issues Found
1. **[Severity: important]** — The worker logging/observability contract is still punted. `WorkerServiceConfig` exposes `loadBalancerLoggingAddr` and the worker PUB connects to it (`lotos/src/Lotos/Zmq/Config.hs:121`, `lotos/src/Lotos/Zmq/LBW.hs:146`), but info storage currently subscribes to `socketLayerSenderAddr` (`lotos/src/Lotos/Zmq/LBS/InfoStorage.hs:89`) and the existing worker literals point logging at `tcp://127.0.0.1:5556` (`applications/TaskSchedule/app/TaskScheduleWorker.hs:31`). The plan says the logging transport should follow “implementation-confirmed framework wiring” while also using logs/status as verification; choose a concrete MVP logging endpoint and acceptance check, or explicitly mark log collection as a known implementation risk/non-MVP check.
2. **[Severity: important]** — The task timeout JSON contract is ambiguous. `Task` has top-level `taskTimeout` (`lotos/src/Lotos/Zmq/Adt.hs:130`), `ClientTask` has `executeTimeoutSec` (`applications/TaskSchedule/src/Adt.hs:161`), but worker execution currently passes `taskTimeout` to `cmdTimeout` (`applications/TaskSchedule/src/Worker.hs:40`). The contract should choose one authoritative timeout field, or state that downstream implementation must map `taskProp.executeTimeoutSec` to the execution timeout.

### Missing Items
- Define ACK semantics precisely: whether the client ACK means “accepted/enqueued” or “completed,” expected client exit behavior on timeout, and note that the current client API waits for an ACK while the server frontend currently only enqueues.

### Suggestions
- Include a small example task JSON and the exact info endpoints/fields that prove an `echo`-style task moved through the MVP path.
