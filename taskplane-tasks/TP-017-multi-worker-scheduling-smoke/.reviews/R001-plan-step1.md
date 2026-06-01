## Plan Review: Step 1: Design multi-worker smoke

### Verdict: REVISE

### Summary
The plan covers the main shape: keep the existing single-worker helper stable, add a separate multi-worker smoke, generate distinct worker configs, collect current-run evidence, and use bounded cleanup. It still has two orchestration gaps that can make the smoke fail or flake before it proves multi-worker scheduling.

### Issues Found
1. **[Severity: important]** — `STATUS.md:88` plans concurrent client submissions but does not define distinct client configs/IDs. `mkClientService` sets the REQ `Z_RoutingId` from `clientId` (`lotos/src/Lotos/Zmq/LBC.hs:34-39`), while the checked-in `applications/TaskSchedule/config/client.json:1-4` uses one `simpleClient_1`; concurrent clients sharing that ROUTER identity can collide or time out. Fix: generate per-run client configs with unique IDs such as `smokeClient_1`/`smokeClient_2`, or avoid concurrent client processes and document a safe sequencing strategy.
2. **[Severity: important]** — The plan defaults to exactly two tasks and assumes concurrent launch means they will batch together (`STATUS.md:88`). The task processor is timer/notify driven, so one task can be dequeued/scheduled before the second is enqueued, making the “each worker has current-run evidence” criterion fail due orchestration race rather than a real scheduler result. Fix: define a deterministic per-worker proof strategy, such as enough fresh tasks and/or long-running marker tasks plus `/worker_tasks` or status polling to show both workers receive current-run work; only classify “all work stayed on one worker” as a scheduling blocker after the smoke has removed client/batching races.

### Missing Items
- Explicit unique client identity/config strategy for concurrent submissions.
- Deterministic approach for proving each worker executed at least one current-run task, not just that both workers registered.

### Suggestions
- The separate-helper decision is a good way to protect the existing green single-worker smoke path.
- In the Step 2 implementation notes, record the exact evidence files that prove per-worker stats, logs, markers, ACKs, garbage absence, and cleanup.
