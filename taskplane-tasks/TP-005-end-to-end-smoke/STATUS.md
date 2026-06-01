# TP-005: TaskSchedule End-to-End Smoke Test — Status

**Current Step:** Step 4: Documentation & Delivery
**Status:** ✅ Complete
**Last Updated:** 2026-05-31
**Review Level:** 2
**Review Counter:** 5
**Iteration:** 3
**Size:** M

---

### Step 0: Preflight
**Status:** ✅ Complete

- [x] Required files and paths exist
- [x] TP-003 and TP-004 completion criteria are satisfied

---

### Step 1: Design smoke approach
**Status:** ✅ Complete

- [x] Commands identified
- [x] Readiness checks/timeouts identified
- [x] Cleanup strategy decided
- [x] R001: Concrete command sequence and working directory assumptions documented
- [x] R001: Bounded readiness/verification probes with pass/fail criteria documented
- [x] R001: Safe cleanup and process-group strategy documented
- [x] R001: Expected ACK/runtime blocker handling documented
- [x] R002: Fresh-run marker/evidence guard documented
- [x] R002: Spawned process health checks documented

---

### Step 2: Implement smoke test/runbook
**Status:** ✅ Complete

- [x] Script or manual fallback added
- [x] Current-run marker/evidence guard implemented
- [x] Spawned server/worker liveness probes implemented
- [x] ACK timeout classified separately from hard failures
- [x] Portable prerequisites/fallback messages implemented
- [x] Simple command submitted through client
- [x] Info/log proof collected
- [x] Cleanup works on success/failure

---

### Step 3: Testing & Verification
**Status:** ✅ Complete

- [x] `cabal build all` passes
- [x] Smoke path executed or blocker documented
- [x] Evidence captured

---

### Step 4: Documentation & Delivery
**Status:** ✅ Complete

- [x] README updated
- [x] MVP contract updated
- [x] Discoveries logged

---

## Reviews

| # | Type | Step | Verdict | File |
|---|------|------|---------|------|
| R001 | plan | 1 | REVISE | `.reviews/R001-plan-step1.md` |
| R002 | plan | 1 | REVISE | `.reviews/R002-plan-step1.md` |
| R003 | plan | 1 | APPROVE | `.reviews/R003-plan-step1.md` |
| R004 | plan | 2 | APPROVE | `.reviews/R004-plan-step2.md` |
| R005 | code | 3 | APPROVE | `.reviews/R005-code-step3.md` |

---

## Discoveries

- 2026-06-01: Local `HTTP_PROXY`/`http_proxy` settings can intercept loopback `curl` calls and return misleading 405 responses; the smoke script and manual docs use `curl --noproxy '*'` for info API probes.
- 2026-06-01: Worker status frames currently fail server backend parsing with `ZmqParsing "Text decode error: Cannot decode byte '\\xe4'"`, preventing `/SimpleServer/worker_stats` from showing `simpleWorker_1`; logged as future work in `taskplane-tasks/CONTEXT.md`.
- 2026-06-01: The known server `ClientAck` gap remains after the worker-registration blocker is fixed; logged as future work in `taskplane-tasks/CONTEXT.md`.

---

## Execution Log

| 2026-05-31 16:51 | Task started | Runtime V2 lane-runner execution |
| 2026-05-31 16:51 | Step 0 started | Preflight |
| 2026-06-01 | Preflight files verified | Confirmed required docs, app entrypoints, config directory, scripts directory, and InfoStorage path exist. |
| 2026-06-01 | Dependency tasks verified | TP-003 and TP-004 STATUS files are ✅ Complete and both .DONE markers are present. |
| 2026-06-01 | Step 0 complete | Preflight complete; proceeding to smoke approach design. |
| 2026-06-01 | Step 1 started | Design smoke approach |
| 2026-06-01 | Step 1 commands | Documented repo-root working directory, setup paths, server/worker/client cabal commands, sample configs, and demo task JSON command. |
| 2026-06-01 | Step 1 readiness | Documented bounded HTTP readiness, worker-registration, client timeout, marker-file, and info endpoint evidence probes with pass/fail criteria. |
| 2026-06-01 | Step 1 cleanup | Documented PID/process-group tracking, trap cleanup, TERM/KILL escalation, and avoidance of broad process kills. |
| 2026-06-01 | Step 1 ACK handling | Documented known server ClientAck gap and how smoke output should classify full pass vs known ACK blocker vs hard failure. |
| 2026-06-01 | Step 1 fresh-run guard | Documented per-run evidence directory, marker path, and exact run-id marker proof to prevent stale smoke evidence. |
| 2026-06-01 | Step 1 process health | Documented spawned server/worker PID liveness checks during readiness and failure log preservation. |
| 2026-06-01 | Step 1 complete | Plan review R003 approved the smoke design; proceeding to implementation. |
| 2026-06-01 | Step 2 hydrated | Added implementation checkpoints for fresh evidence, process health, ACK blocker classification, and portability messaging. |
| 2026-06-01 | Step 2 plan approved | Plan review R004 approved the smoke implementation checkpoints. |
| 2026-06-01 | Step 2 script added | Added executable scripts/task-schedule-smoke.sh and verified shell syntax with bash -n. |
| 2026-06-01 | Step 2 fresh evidence | Implemented unique run IDs, per-run evidence directories, per-run task JSON, marker cleanup, and exact marker-content verification. |
| 2026-06-01 | Step 2 process liveness | Implemented tracked server/worker PIDs, process-group targets, kill -0 checks during readiness/marker polling, and early failure log preservation. |
| 2026-06-01 | Step 2 ACK classification | Implemented distinct PASS, KNOWN_ACK_BLOCKER (exit 2), and hard FAIL outcomes with result.env details. |
| 2026-06-01 | Step 2 portability | Implemented required command checks plus explicit timeout(1) and setsid(1) fallback warnings. |
| 2026-06-01 | Step 2 client submission | Script writes a validated TaskSchedule task JSON and submits it via cabal run TaskSchedule:exe:ts-client with the sample client config. |
| 2026-06-01 | Step 2 evidence collection | Script snapshots info/tasks/worker_tasks/worker_stats/garbage endpoints and extracts run-id matches from TaskSchedule logs into the evidence directory. |
| 2026-06-01 | Step 2 cleanup | Implemented EXIT/INT/TERM traps that clean only tracked PIDs/process groups with TERM then KILL escalation while preserving evidence. |
| 2026-05-31 17:00 | Worker iter 1 | done in 581s, tools: 48 |
| 2026-05-31 17:14 | Worker iter 2 | done in 824s, tools: 76 |
| 2026-05-31 17:14 | Step 3 started | Testing & Verification |
| 2026-06-01 | Step 3 build | `cabal build all` completed successfully (`Up to date`). |
| 2026-06-01 | Step 3 smoke run | Executed `scripts/task-schedule-smoke.sh` after adding local curl proxy bypass; run `task-schedule-smoke-20260531T171828Z-3077658` exited 1 because the worker never appeared in `/SimpleServer/worker_stats`. Server log shows repeated `ZmqParsing "Text decode error: Cannot decode byte '\\xe4'"` while handling backend worker status messages. |
| 2026-06-01 | Step 3 evidence | Captured build output, smoke `result.env`, worker_stats snapshot, server parse-error snippets, and cleanup proof (no TaskSchedule processes or smoke ports left listening). |
| 2026-06-01 | Review R005 | code Step 3: APPROVE |
| 2026-06-01 | Step 3 complete | Code review R005 approved the smoke script and verification evidence; proceeding to documentation delivery. |
| 2026-06-01 | Step 4 started | Documentation and delivery updates. |
| 2026-06-01 | Step 4 README | Added smoke helper command, evidence directory, exit-code meanings, cleanup behavior, and current worker-registration blocker to README.md. |
| 2026-06-01 | Step 4 MVP contract | Updated docs/task-schedule-mvp.md with smoke helper instructions, manual fallback using local proxy bypass, TP-005 verification evidence, and current worker status parsing blocker. |
| 2026-06-01 | Step 4 discoveries | Logged loopback proxy behavior, worker status frame decode blocker, and follow-up ClientAck gap in STATUS.md and taskplane-tasks/CONTEXT.md. |
| 2026-06-01 | Step 4 complete | Documentation and delivery complete. |
| 2026-06-01 | Task complete | All TP-005 steps complete; smoke path is repeatable and documents the current runtime blocker. |
| 2026-05-31 17:28 | Worker iter 3 | done in 826s, tools: 69 |
| 2026-05-31 17:28 | Task complete | .DONE created |
---

## Blockers

- 2026-06-01: End-to-end smoke cannot reach task submission yet. Evidence run `.tmp/task-schedule-smoke/task-schedule-smoke-20260531T171828Z-3077658/` shows server readiness passed, worker stayed alive and reported status locally, but the server logged repeated backend `ZmqParsing "Text decode error: Cannot decode byte '\\xe4': Data.Text.Encoding: Invalid UTF-8 stream"` errors and `/SimpleServer/worker_stats` remained `{"stats":{},"type":"WorkerStat"}` until timeout.

---

## Notes

### Step 3 verification evidence

- Build: `cabal build all` completed successfully with `Up to date`.
- Smoke command: `bash -n scripts/task-schedule-smoke.sh && scripts/task-schedule-smoke.sh`.
- Evidence run: `.tmp/task-schedule-smoke/task-schedule-smoke-20260531T171828Z-3077658/`.
- Smoke result: `result.env` contains `status=FAIL`, `detail=worker did not register`, and no client exit because submission was correctly skipped until worker readiness.
- Readiness proof: `server-ready-info.json` was fetched successfully after forcing local curl requests to bypass proxy settings; `worker-ready-worker_stats.json` remained `{"stats":{},"type":"WorkerStat"}`.
- Runtime blocker proof: `server-stdio.log` repeatedly records `ZmqParsing "Text decode error: Cannot decode byte '\\xe4': Data.Text.Encoding: Invalid UTF-8 stream"` immediately after `handleBackend: recv worker request`, while `worker-stdio.log` shows the worker stayed alive and emitted `Worker status: WorkerState ...` reports.
- Cleanup proof: after the failed run, `ps` found no TaskSchedule/cabal smoke processes and `ss` showed no listeners on 8081, 5555, 5556, or 5557.

### Step 1 smoke design

- Working directory: run from the repository root so `cabal run`, `logs/`, `.tmp/`, checked-in sample configs, and the worker's demo output use predictable relative paths.
- Command sequence: create `logs/` and `.tmp/task-schedule-smoke/`; write `.tmp/task-schedule-smoke/task-demo.json`; start `cabal run TaskSchedule:exe:ts-server -- applications/TaskSchedule/config/broker.json` in the background; start `cabal run TaskSchedule:exe:ts-worker -- applications/TaskSchedule/config/worker.json` in the background after server readiness; submit `cabal run TaskSchedule:exe:ts-client -- applications/TaskSchedule/config/client.json .tmp/task-schedule-smoke/task-demo.json`; capture server/worker/client stdout/stderr and info endpoint snapshots under `.tmp/task-schedule-smoke/`.
- Demo task command: `mkdir -p .tmp && printf 'task-schedule-ok\n' > .tmp/task-schedule-demo.out` with both `taskTimeout` and `taskProp.executeTimeoutSec` set to `5`.
- Readiness and timeout probes: poll `http://127.0.0.1:8081/SimpleServer/info` with `curl -fsS` for up to 60s; poll `/SimpleServer/worker_stats` for up to 90s until it contains `simpleWorker_1` (worker reports every 5s and info storage refreshes every 10s); wrap the client command with a bounded shell `timeout` (default 60s) while preserving the client log; after submission, poll `.tmp/task-schedule-demo.out` for up to 30s and snapshot `/tasks`, `/worker_tasks`, `/worker_stats`, and `/garbage` for evidence.
- Pass/fail criteria: full pass requires client exit `0`, worker registration, marker file content `task-schedule-ok`, and no demo task in garbage; a client non-zero ACK timeout with marker/info proof is classified as the known ACK blocker rather than a generic orchestration failure; missing server/worker readiness, missing marker, or garbage evidence remains a smoke failure.
- Cleanup strategy: track only PIDs spawned by the smoke script; start server and worker in their own process groups where `setsid` is available; install a `trap` for `EXIT`, `INT`, and `TERM`; on cleanup send TERM to each tracked process group (or tracked PID fallback), wait briefly, then send KILL if needed. Never use broad `pkill cabal`, `pkill ghc`, or port-based kills that could terminate unrelated developer processes. Preserve `.tmp/task-schedule-smoke/` evidence logs after cleanup.
- Expected ACK/runtime blocker handling: `docs/task-schedule-mvp.md` and `lotos/src/Lotos/Zmq/LBS/SocketLayer.hs` document the current server frontend gap: `handleFrontend` fills a task ID and enqueues the task but does not send `ClientAck` to the waiting client. The smoke script should therefore distinguish (a) full pass when `ts-client` receives ACK and marker proof exists, (b) known `ClientAck` blocker when `ts-client` times out but the marker/info evidence proves the task reached the worker, and (c) hard failure when readiness, worker execution, marker proof, or cleanup fails.
- Fresh-run evidence guard: each smoke run creates a unique evidence directory under `.tmp/task-schedule-smoke/run-<timestamp>-<pid>/`, writes the task JSON there, embeds that run ID in the shell command, writes the marker to that same run directory, and verifies the marker content equals the current run ID. The script must remove any pre-existing marker at that unique path before submission and must never accept `.tmp/task-schedule-demo.out` or another shared marker as proof.
- Spawned process health checks: while polling HTTP readiness and worker registration, the script must check that the tracked server and worker PIDs are still alive with `kill -0 <pid>` (or process-group equivalent) before each probe. If either spawned process exits early, readiness fails immediately, the script records the exit/health failure in the evidence directory, preserves the relevant logs, runs normal cleanup for any remaining process, and does not proceed against a possibly stale already-running service on the same ports.

### Step 1 review notes

- R001 suggestion: write the concrete smoke design into STATUS.md under Step 1 before implementing, so the script/runbook has a clear reviewable contract.
- R002 suggestion: consider recording a run ID in task content/log filenames so endpoint snapshots and garbage checks can be correlated to the current submission.

| 2026-05-31 16:54 | Review R001 | plan Step 1: REVISE |
| 2026-05-31 17:00 | Review R002 | plan Step 1: REVISE |
| 2026-05-31 17:04 | Review R003 | plan Step 1: APPROVE |
| 2026-05-31 17:08 | Review R004 | plan Step 2: APPROVE |
| 2026-05-31 17:24 | Review R005 | code Step 3: APPROVE |
