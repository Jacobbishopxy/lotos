## Plan Review: Step 1: Design smoke approach

### Verdict: REVISE

### Summary
The submitted STATUS only lists the Step 1 outcomes as unchecked placeholders; it does not record an actual smoke design to review. Because this step is specifically the plan-review checkpoint for process orchestration and cleanup, the worker should capture concrete decisions before moving on to the script/runbook.

### Issues Found
1. **[Severity: important]** — The plan does not identify the actual server, worker, and client commands required by PROMPT.md lines 66-68. Add the chosen commands from `docs/task-schedule-mvp.md`, e.g. `mkdir -p logs .tmp`, `cabal run TaskSchedule:exe:ts-server -- [broker config]`, `cabal run TaskSchedule:exe:ts-worker -- [worker config]`, and `cabal run TaskSchedule:exe:ts-client -- [client config] <task-json>`.
2. **[Severity: important]** — The plan does not define readiness checks or timeout behavior. Add explicit bounded waits for the server info API (`/SimpleServer/info`), worker registration (`/SimpleServer/worker_stats` containing `simpleWorker_1` after the status interval), client ACK/timeout handling, and final observable proof via the marker file and/or info endpoints.
3. **[Severity: important]** — The plan does not decide a cleanup strategy, despite the task's explicit “Do NOT leave background server/worker processes running” requirement. Specify PID tracking, `trap`-based cleanup on success/failure/interrupt, log capture, and how to kill child process groups without terminating unrelated Cabal/GHC processes.
4. **[Severity: important]** — The plan does not account for the known ACK/runtime gap documented in `docs/task-schedule-mvp.md` and visible in `Lotos/Zmq/LBS/SocketLayer.hs` where the frontend enqueues but does not send `ClientAck`. The smoke design must decide whether the expected result is a successful run or an exact documented blocker, so Step 2 does not hide an expected client timeout as a generic script failure.

### Missing Items
- Concrete smoke command sequence and working-directory assumptions.
- Bounded readiness/verification probes with pass/fail criteria.
- Safe cleanup design for all spawned long-running processes.
- Explicit handling of expected runtime blockers versus successful end-to-end acceptance.

### Suggestions
- Prefer writing the design into STATUS.md under Step 1 before implementing; this gives the code-review checkpoint a clear contract for the script/runbook.
