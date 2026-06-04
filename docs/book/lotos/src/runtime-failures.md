# Runtime Failure Runbook

This runbook helps operators diagnose runtime failures in the Lotos ZeroMQ load-balancer and the TaskSchedule demo without assuming stronger delivery guarantees than the system provides. It focuses on observable symptoms, evidence to collect, and safe recovery choices.

Use `curl --noproxy '*'` for local HTTP probes in proxy-enabled environments. The examples below use the default TaskSchedule HTTP prefix, `/SimpleServer`.

## Operator-visible symptoms

| Symptom | What operators usually see | First question to answer |
| --- | --- | --- |
| Stuck worker | A worker stays present but stops completing assigned tasks, or its task count never decreases. | Is the worker still reporting fresh status, and are its task logs moving? |
| No task progress | Submitted tasks receive ACKs but remain queued, retrying, or assigned without visible side effects. | Are tasks waiting for scheduler capacity, blocked in a worker, or moved to failed/garbage state? |
| Broker overload | Broker runtime handoff queues grow or repeatedly set new high-water depths. | Which no-drop handoff queue is accumulating faster than the owner thread drains it? |
| LogIngest backlog | Worker logs arrive late, `/logs/stats` rejected/drop/sequence counters increase, or worker log transport reports ACK timeouts/retries. | Is the logging path overloaded while task/status traffic remains healthy? |
| Stale heartbeats | A worker disappears from worker stats after missing the stale timeout, and its non-succeeded in-flight tasks re-enter retry/garbage handling. | Was the worker process/network actually lost, or is the heartbeat interval/stale timeout too aggressive for this deployment? |
| Reservation underutilization | Capacity appears lower than expected immediately after dispatch, especially during bursts. | Are conservative broker reservations still protecting slots until the next heartbeat reflects the assignment? |
| Smoke failure | `make smoke-single`, `make smoke-multi`, or the direct smoke scripts fail with missing ACKs, stats, logs, side-effect files, or capacity assertions. | Which expected evidence artifact is missing from the generated `.tmp/` run directory and endpoint probes? |

## Evidence sources

Collect the smallest evidence set that distinguishes scheduler delay, worker loss, broker overload, and logging-path pressure.

| Evidence source | What it proves | Useful fields or observations |
| --- | --- | --- |
| `/SimpleServer/info` | Read-only scheduler snapshot: queued tasks, failed/retry queue payloads, garbage tasks, per-worker task assignment, worker status, and runtime handoff queue stats. | `tasksInQueue`, `tasksInFailedQueue`, `tasksInGarbageBin`, `workerTasksMap`, `workerStatusMap`, `runtimeQueueStats`. |
| `/SimpleServer/info.runtimeQueueStats` | Broker and worker handoff pressure for no-drop task/status paths. | Queue `name`, `currentDepth`, `highWaterDepth`, `totalEnqueued`, `totalDrained`, `warningThreshold`. Rising depth is overload evidence, not proof of dropped task/status frames. |
| `/SimpleServer/tasks` | Queued and retryable task state without the rest of `/info`. | Response type `TaskQueues`, with `queued` and `running` fields as exposed by the current API. |
| `/SimpleServer/worker_tasks` | Broker-known tasks currently assigned to each worker. | Response type `WorkerTasks`, keyed by worker routing id. Compare with worker logs and task side effects. |
| `/SimpleServer/worker_stats` | Latest heartbeat/status payloads per worker. | TaskSchedule status fields include `processingTaskNum`, `waitingTaskNum`, and `taskCapacity`; absence or stale values indicate heartbeat/liveness problems. |
| `/SimpleServer/garbage` | Tasks that exhausted retry policy or were otherwise placed in the garbage ring buffer. | Response type `Garbage`; inspect task ids and payloads before resubmitting. |
| `/SimpleServer/logs/recent` | Recent accepted worker log events across workers/tasks. | Confirms LogIngest accepted current-run events; absence may be logging-path-specific. |
| `/SimpleServer/logs/worker/<workerId>` | Accepted log stream for one worker. | Use stdout/result/error events to identify hung command execution or worker-side failures. |
| `/SimpleServer/logs/task/<taskUuid>` | Accepted log stream for one task. | Confirms whether a specific assigned task started, emitted output, or produced a result event. |
| `/SimpleServer/logs/stats` | LogIngest-only accepted/duplicate/gap/drop/reject accounting. | `acceptedEvents`, `duplicateEvents`, `sequenceGaps`, `droppedEvents`, `rejectedEvents`, `malformedJournalLines`, `workers`, `tasks`, `acceptedThroughByWorker`. Do not read these counters as task/status queue loss. |
| Worker process logs | Worker transport state and LogIngest retry/ACK behavior. | Look for backend connection errors, task execution failures, `worker LogIngest ACK timeout`, ACK rejected entries, or stopped EventLoop messages. |
| Broker process logs | Broker overload and stale-worker recovery decisions. | Look for handoff queue WARN messages, LogIngest EventLoop errors, task processor retries, or stale-worker recovery logs. |
| Smoke output and `.tmp/` artifacts | Reproducible current-run evidence for examples. | Smoke helpers generate run-local configs/evidence under `.tmp/`, probe HTTP endpoints, check marker files, and clean up tracked process groups. |

## Missing signals to treat as future work

Do not invent recovery evidence that the runtime does not currently expose. When these questions matter, record the limitation in the incident notes and add follow-up work rather than changing operator procedure mid-incident.

- There is no dedicated heartbeat-age field in `/worker_stats`; freshness is inferred from worker presence, status changes, broker logs, and the configured `workerStaleTimeoutSec`.
- `runtimeQueueStats` reports handoff queue depth/counters, but it does not name a causal task, worker, or scheduler decision for each enqueue.
- Capacity reservations are broker-internal safety markers. Operators can infer their effect by comparing `/worker_stats` capacity fields with `/worker_tasks`, but there is no separate public reservations endpoint.
- LogIngest exposes accepted/duplicate/gap/drop/reject counters and accepted-through sequence state, not an exactly-once delivery proof.
- Smoke helpers write generated evidence under `.tmp/`, but they are not continuous monitoring; use them for bounded reproduction and release checks.

## Safe recovery procedures

### Stuck worker and stale heartbeat recovery

1. Capture current broker snapshots before restarting anything:
   ```bash
   curl --noproxy '*' http://127.0.0.1:8081/SimpleServer/info
   curl --noproxy '*' http://127.0.0.1:8081/SimpleServer/worker_stats
   curl --noproxy '*' http://127.0.0.1:8081/SimpleServer/worker_tasks
   curl --noproxy '*' http://127.0.0.1:8081/SimpleServer/logs/recent
   ```
2. Identify the worker routing id from `/worker_stats` and `/worker_tasks`. Compare `processingTaskNum`, `waitingTaskNum`, and `taskCapacity` with the broker-known task list.
3. Query worker and task logs. If task logs show command output/result progress, prefer waiting or fixing the downstream command over restarting the worker.
4. If the worker stopped reporting heartbeats, let broker stale-worker recovery run before manually resubmitting tasks. The broker removes stale worker status/task buckets and sends non-succeeded in-flight tasks through the normal retry/garbage path after `workerStaleTimeoutSec`.
5. Restart only the affected worker process when process logs show it is wedged, disconnected, or its backend EventLoop has stopped. Do not restart the broker first unless broker probes/logs show broker-side failure; broker restart is a wider disruption and may obscure the original evidence.
6. After restart or stale recovery, re-check `/worker_stats`, `/worker_tasks`, `/tasks`, `/garbage`, and relevant task logs. Resubmit from the client side only for tasks that are in garbage or otherwise proven not to be queued, assigned, retrying, or completed.

### LogIngest backlog or missing log events

1. Separate logging-path symptoms from task/status symptoms. `/logs/stats` is LogIngest-only; use `/info.runtimeQueueStats` for task/status handoff pressure.
2. Capture:
   ```bash
   curl --noproxy '*' http://127.0.0.1:8081/SimpleServer/logs/stats
   curl --noproxy '*' http://127.0.0.1:8081/SimpleServer/logs/recent
   curl --noproxy '*' http://127.0.0.1:8081/SimpleServer/info
   ```
3. Interpret counters conservatively:
   - `acceptedEvents` increasing means the broker is accepting LogIngest records.
   - `duplicateEvents` can be normal after worker retry; dedupe makes retries idempotent.
   - `sequenceGaps`, `droppedEvents`, and `rejectedEvents` indicate lost visibility or broker-side dispatch pressure in the logging path, not lost task/status protocol frames.
   - `malformedJournalLines` points to journal corruption or manual edits and should be preserved for post-incident analysis.
4. Check worker logs for `worker LogIngest ACK timeout`, ACK rejected entries, stopped EventLoop messages, or endpoint mismatches. Retry is expected when ACKs are delayed; the transport is at-least-once with idempotent ingestion, not exactly-once.
5. If logging is backlogged but tasks are progressing, avoid restarting healthy workers just to flush logs. Reduce log volume, fix the LogIngest endpoint/configuration, or restart the broker LogIngest owner only if broker logs show the logging EventLoop failed.
6. Preserve the journal path from the active `logIngest.logIngestJournalPath` before deleting generated state. For smoke runs, prefer a fresh run-local journal under `.tmp/` so old accepted sequences do not hide current-run events as duplicates.

### Broker overload and handoff queue growth

1. Inspect `runtimeQueueStats` from `/info` and identify which queue name has a rising `currentDepth` or repeatedly increasing `highWaterDepth`:
   ```bash
   curl --noproxy '*' http://127.0.0.1:8081/SimpleServer/info | jq '.runtimeQueueStats'
   ```
2. Treat task/status handoff queues as protocol-critical no-drop queues. Do not recover overload by dropping task, status, heartbeat, or ACK frames. The safe response is to reduce ingress, increase worker/scheduler capacity, or fix the slow consumer.
3. Compare `totalEnqueued` and `totalDrained` over time. If both increase but depth remains high, the owner thread is draining too slowly for incoming load. If enqueued rises while drained stalls, inspect the owner thread logs for exceptions or a blocked downstream operation.
4. Correlate queue pressure with `/tasks`, `/worker_stats`, and `/worker_tasks`:
   - many queued tasks plus idle worker capacity points at scheduler/backend dispatch problems;
   - full worker capacity plus long task logs points at downstream task execution;
   - growing status/heartbeat handoff pressure points at a broker-side status processing bottleneck.
5. Remediate by pausing new client submissions, adding workers, shortening expensive task commands, or widening scheduler/task-processor throughput only after measuring the slow path. Keep logs and snapshots for follow-up capacity planning.

### Capacity reservation underutilization

TaskSchedule capacity is heartbeat-based, while the broker also keeps conservative reservations for tasks it has assigned but may not yet see reflected in the next worker status snapshot. This prevents burst over-assignment, but it can look like temporary underutilization.

1. Compare `/worker_stats` with `/worker_tasks`. If `processingTaskNum + waitingTaskNum` is below `taskCapacity` but `/worker_tasks` already shows recent assignments for that worker, reservations may be protecting those slots until a heartbeat catches up.
2. Wait at least one heartbeat/status refresh interval before declaring capacity lost, unless worker logs show the worker is down or not accepting tasks.
3. Use the multi-worker smoke evidence as a known-good model: capacity-1 generated workers should not receive more in-flight work than their configured slots during burst dispatch.
4. If underutilization persists across multiple heartbeat intervals, inspect scheduler logic, worker acceptor behavior, and task execution duration. Do not manually edit broker state; restart an affected worker only when its process is unhealthy, and let stale recovery/retry handling reconcile its tasks.
5. Document any chronic reservation lag as future tuning work. The current behavior intentionally favors avoiding over-assignment over perfect instantaneous utilization.

### Smoke failure triage

1. Re-run the failing helper directly so its output names the missing evidence:
   ```bash
   scripts/task-schedule-smoke.sh
   scripts/task-schedule-multi-worker-smoke.sh
   ```
   or through:
   ```bash
   make smoke-single
   make smoke-multi
   ```
2. Inspect the generated run-local files under `.tmp/`. The smoke helpers create configs, logs, marker files, HTTP probe output, and run identifiers there, then clean up only the process groups they started.
3. Match the failure to the evidence class:
   - missing client ACK: check frontend/backend addresses and protocol frame preservation;
   - missing marker file or command output: inspect worker process logs and task logs;
   - missing `/logs/*` events: verify LogIngest endpoint alignment and current-run journal isolation;
   - dirty `/logs/stats`: inspect rejected/drop/sequence counters and worker ACK retry logs;
   - missing `runtimeQueueStats`: inspect `/info` and the broker build/config used by the run;
   - multi-worker capacity assertion failure: compare `/worker_stats` and `/worker_tasks` snapshots for reservation-safe dispatch.
4. Do not use smoke cleanup as production recovery. Smoke helpers are bounded verification tools; production incidents should preserve logs, journals, and HTTP snapshots before restart or state cleanup.

