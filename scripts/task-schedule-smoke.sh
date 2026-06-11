#!/usr/bin/env bash
# Repeatable end-to-end smoke path for the TaskSchedule demo.
#
# Exit codes:
#   0 - full MVP pass: client received ACK and worker marker proof exists
#   1 - hard smoke failure, including missing ACK, marker, readiness, or garbage checks

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

RUN_ID="${SMOKE_RUN_ID:-task-schedule-smoke-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
EVIDENCE_ROOT="${SMOKE_EVIDENCE_ROOT:-.tmp/task-schedule-smoke}"
EVIDENCE_DIR="${SMOKE_EVIDENCE_DIR:-$EVIDENCE_ROOT/$RUN_ID}"
MARKER_FILE="$EVIDENCE_DIR/marker.txt"
TASK_TOML="$EVIDENCE_DIR/task-demo.toml"
RUN_LOG="$EVIDENCE_DIR/smoke.log"
SERVER_STDIO_LOG="$EVIDENCE_DIR/server-stdio.log"
WORKER_STDIO_LOG="$EVIDENCE_DIR/worker-stdio.log"
CLIENT_STDIO_LOG="$EVIDENCE_DIR/client-stdio.log"
RESULT_FILE="$EVIDENCE_DIR/result.env"

if [ -n "${SMOKE_BROKER_CONFIG:-}" ]; then
  BROKER_CONFIG="$SMOKE_BROKER_CONFIG"
  GENERATE_BROKER_CONFIG=0
else
  BROKER_CONFIG="$EVIDENCE_DIR/broker.json"
  GENERATE_BROKER_CONFIG=1
fi
WORKER_CONFIG="${SMOKE_WORKER_CONFIG:-applications/TaskSchedule/config/worker.json}"
CLIENT_CONFIG="${SMOKE_CLIENT_CONFIG:-applications/TaskSchedule/config/client.json}"
INFO_BASE="${SMOKE_INFO_BASE:-http://127.0.0.1:8081/SimpleServer}"
WORKER_ID="${SMOKE_WORKER_ID:-simpleWorker_1}"
LOG_INGEST_ADDR="${SMOKE_LOG_INGEST_ADDR:-tcp://127.0.0.1:5558}"
LOG_INGEST_JOURNAL_PATH="${SMOKE_LOG_INGEST_JOURNAL_PATH:-$EVIDENCE_DIR/worker-logs.journal}"
SERVER_READY_TIMEOUT_SEC="${SMOKE_SERVER_READY_TIMEOUT_SEC:-120}"
WORKER_READY_TIMEOUT_SEC="${SMOKE_WORKER_READY_TIMEOUT_SEC:-120}"
CLIENT_TIMEOUT_SEC="${SMOKE_CLIENT_TIMEOUT_SEC:-60}"
MARKER_TIMEOUT_SEC="${SMOKE_MARKER_TIMEOUT_SEC:-30}"
LOGGING_TIMEOUT_SEC="${SMOKE_LOGGING_TIMEOUT_SEC:-45}"
RUNTIME_STATS_TIMEOUT_SEC="${SMOKE_RUNTIME_STATS_TIMEOUT_SEC:-45}"
TASK_TIMEOUT_SEC="${SMOKE_TASK_TIMEOUT_SEC:-5}"

mkdir -p "$EVIDENCE_DIR" logs
: >"$RUN_LOG"

PROCESS_NAMES=()
PROCESS_PIDS=()
PROCESS_TARGETS=()

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$RUN_LOG"
}

write_result() {
  local status="$1"
  local client_exit="${2:-}"
  local detail="${3:-}"
  {
    printf 'status=%s\n' "$status"
    printf 'run_id=%s\n' "$RUN_ID"
    printf 'evidence_dir=%s\n' "$EVIDENCE_DIR"
    printf 'marker_file=%s\n' "$MARKER_FILE"
    printf 'client_exit=%s\n' "$client_exit"
    printf 'detail=%s\n' "$detail"
  } >"$RESULT_FILE"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

curl_local() {
  curl --noproxy '*' "$@"
}

fail_hard() {
  local message="$1"
  log "FAIL: $message"
  write_result "FAIL" "${CLIENT_EXIT:-}" "$message"
  collect_log_extracts || true
  exit 1
}

cleanup_processes() {
  local idx name pid target
  for ((idx=${#PROCESS_PIDS[@]} - 1; idx>=0; idx--)); do
    name="${PROCESS_NAMES[$idx]}"
    pid="${PROCESS_PIDS[$idx]}"
    target="${PROCESS_TARGETS[$idx]}"
    if kill -0 "$pid" >/dev/null 2>&1; then
      log "cleanup: sending TERM to $name (pid=$pid target=$target)"
      kill -TERM -- "$target" >/dev/null 2>&1 || true
    fi
  done

  for ((idx=${#PROCESS_PIDS[@]} - 1; idx>=0; idx--)); do
    name="${PROCESS_NAMES[$idx]}"
    pid="${PROCESS_PIDS[$idx]}"
    target="${PROCESS_TARGETS[$idx]}"
    local waited=0
    while kill -0 "$pid" >/dev/null 2>&1 && [ "$waited" -lt 5 ]; do
      sleep 1
      waited=$((waited + 1))
    done
    if kill -0 "$pid" >/dev/null 2>&1; then
      log "cleanup: sending KILL to $name (pid=$pid target=$target)"
      kill -KILL -- "$target" >/dev/null 2>&1 || true
    fi
    wait "$pid" >/dev/null 2>&1 || true
  done
}

on_exit() {
  local status=$?
  trap - EXIT INT TERM
  cleanup_processes || true
  if [ "$status" -ne 0 ]; then
    log "smoke exiting with status $status; evidence preserved at $EVIDENCE_DIR"
  else
    log "smoke complete; evidence preserved at $EVIDENCE_DIR"
  fi
  exit "$status"
}

trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

require_prerequisites() {
  local missing=0
  for cmd in cabal curl grep date mkdir cat printf sleep; do
    if ! have_cmd "$cmd"; then
      printf 'Missing required command: %s\n' "$cmd" >&2
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    exit 1
  fi

  if ! have_cmd timeout; then
    log "WARNING: timeout(1) not found; relying on ts-client reqTimeoutSec and SMOKE_CLIENT_TIMEOUT_SEC is not enforced externally."
  fi
  if ! have_cmd setsid; then
    log "WARNING: setsid(1) not found; cleanup will target tracked PIDs instead of dedicated process groups."
  fi
}

ensure_config_exists() {
  local path="$1"
  local label="$2"
  if [ ! -f "$path" ]; then
    fail_hard "$label config not found: $path"
  fi
}

ensure_no_existing_info_server() {
  local preflight="$EVIDENCE_DIR/preexisting-info.json"
  if curl_local -fsS --max-time 1 "$INFO_BASE/info" >"$preflight" 2>"$EVIDENCE_DIR/preexisting-info.err"; then
    fail_hard "info endpoint was already responding before smoke server start; stop the existing service or change SMOKE_INFO_BASE"
  fi
  rm -f "$preflight" "$EVIDENCE_DIR/preexisting-info.err"
}

start_tracked() {
  local name="$1"
  local log_file="$2"
  shift 2
  local pid target

  log "starting $name: $*"
  if have_cmd setsid; then
    setsid "$@" >"$log_file" 2>&1 &
    pid=$!
    target="-$pid"
  else
    "$@" >"$log_file" 2>&1 &
    pid=$!
    target="$pid"
  fi

  PROCESS_NAMES+=("$name")
  PROCESS_PIDS+=("$pid")
  PROCESS_TARGETS+=("$target")
  log "started $name pid=$pid target=$target log=$log_file"
}

ensure_alive() {
  local name="$1"
  local pid="$2"
  local log_file="$3"
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    log "$name exited before readiness/pass criterion was met; see $log_file"
    return 1
  fi
  return 0
}

snapshot_endpoint() {
  local endpoint="$1"
  local file="$2"
  curl_local -fsS "$INFO_BASE/$endpoint" >"$file" 2>"$file.err"
}

snapshot_all() {
  local label="$1"
  local endpoint endpoint_label file
  for endpoint in info tasks worker_tasks worker_stats garbage logs/recent logs/stats; do
    endpoint_label="${endpoint//\//_}"
    file="$EVIDENCE_DIR/${label}-${endpoint_label}.json"
    if snapshot_endpoint "$endpoint" "$file"; then
      rm -f "$file.err"
    else
      log "snapshot warning: failed to fetch $endpoint into $file (stderr in $file.err)"
    fi
  done
}

info_has_runtime_queue_stats() {
  local file="$1"
  local field queue_name
  grep -F '"runtimeQueueStats":[' "$file" >/dev/null 2>&1 || return 1
  for field in name currentDepth highWaterDepth totalEnqueued totalDrained warningThreshold; do
    grep -F "\"$field\"" "$file" >/dev/null 2>&1 || return 1
  done
  for queue_name in broker.task.queue broker.failed-task.queue broker.socketlayer.frontend-frames broker.socketlayer.backend-frames broker.socketlayer.taskprocessor-frames; do
    grep -F "\"name\":\"$queue_name\"" "$file" >/dev/null 2>&1 || return 1
  done
  grep -F '"workerLivenessMap":{' "$file" >/dev/null 2>&1 || return 1
  grep -F '"workerReservationMap":{' "$file" >/dev/null 2>&1 || return 1
  grep -F "\"$WORKER_ID\"" "$file" >/dev/null 2>&1 || return 1
  for field in lastSeen staleTimeoutSec heartbeatAgeSec stale; do
    grep -F "\"$field\"" "$file" >/dev/null 2>&1 || return 1
  done
  return 0
}

wait_for_runtime_queue_stats() {
  local server_pid="$1"
  local worker_pid="$2"
  local info_file="$EVIDENCE_DIR/runtime-queue-stats-info.json"
  local deadline=$((SECONDS + RUNTIME_STATS_TIMEOUT_SEC))
  while [ "$SECONDS" -le "$deadline" ]; do
    ensure_alive "server" "$server_pid" "$SERVER_STDIO_LOG" || return 1
    ensure_alive "worker" "$worker_pid" "$WORKER_STDIO_LOG" || return 1
    if snapshot_endpoint "info" "$info_file"; then
      rm -f "$info_file.err"
      if info_has_runtime_queue_stats "$info_file"; then
        log "runtime queue stats, worker liveness, and reservation maps found in /info without requiring nonzero backlog"
        return 0
      fi
    fi
    sleep 1
  done
  log "runtime diagnostics timed out after ${RUNTIME_STATS_TIMEOUT_SEC}s"
  return 1
}

wait_for_server() {
  local server_pid="$1"
  local deadline=$((SECONDS + SERVER_READY_TIMEOUT_SEC))
  while [ "$SECONDS" -le "$deadline" ]; do
    ensure_alive "server" "$server_pid" "$SERVER_STDIO_LOG" || return 1
    if snapshot_endpoint "info" "$EVIDENCE_DIR/server-ready-info.json"; then
      rm -f "$EVIDENCE_DIR/server-ready-info.json.err"
      log "server info endpoint is ready"
      return 0
    fi
    sleep 1
  done
  log "server readiness timed out after ${SERVER_READY_TIMEOUT_SEC}s"
  return 1
}

wait_for_worker() {
  local server_pid="$1"
  local worker_pid="$2"
  local deadline=$((SECONDS + WORKER_READY_TIMEOUT_SEC))
  while [ "$SECONDS" -le "$deadline" ]; do
    ensure_alive "server" "$server_pid" "$SERVER_STDIO_LOG" || return 1
    ensure_alive "worker" "$worker_pid" "$WORKER_STDIO_LOG" || return 1
    if snapshot_endpoint "worker_stats" "$EVIDENCE_DIR/worker-ready-worker_stats.json"; then
      rm -f "$EVIDENCE_DIR/worker-ready-worker_stats.json.err"
      if grep -F "$WORKER_ID" "$EVIDENCE_DIR/worker-ready-worker_stats.json" >/dev/null 2>&1; then
        log "worker $WORKER_ID is registered"
        return 0
      fi
    fi
    sleep 1
  done
  log "worker readiness timed out after ${WORKER_READY_TIMEOUT_SEC}s"
  return 1
}

write_broker_config() {
  if [ "$GENERATE_BROKER_CONFIG" -eq 0 ]; then
    log "using caller-provided broker config $BROKER_CONFIG"
    return 0
  fi

  cat >"$BROKER_CONFIG" <<JSON
{
  "taskScheduler": {
    "taskQueueHWM": 1000,
    "failedTaskQueueHWM": 1000,
    "garbageBinSize": 100
  },
  "socketLayer": {
    "frontendAddr": "tcp://127.0.0.1:5555",
    "backendAddr": "tcp://127.0.0.1:5556"
  },
  "taskProcessor": {
    "taskQueuePullNo": 10,
    "failedTaskQueuePullNo": 10,
    "triggerAlgoMaxNotifyCount": 10,
    "triggerAlgoMaxWaitSec": 10,
    "workerStaleTimeoutSec": 60
  },
  "infoStorage": {
    "httpPort": 8081,
    "loggingAddr": "tcp://127.0.0.1:5557",
    "loggingsBufferSize": 1000,
    "infoFetchIntervalSec": 10
  },
  "logIngest": {
    "logIngestAddr": "$LOG_INGEST_ADDR",
    "logIngestSocketHWM": 1000,
    "logIngestBatchMaxRecords": 100,
    "logIngestBatchMaxBytes": 1048576,
    "logIngestLineMaxBytes": 65536,
    "logIngestWorkerQueueHWM": 10000,
    "logIngestFlushIntervalMicros": 100000,
    "logIngestAckTimeoutMicros": 1000000,
    "logIngestRetryBackoffMicros": 250000,
    "logIngestReadCacheSize": 1000,
    "logIngestReadCacheMaxTasks": 1000,
    "logIngestJournalPath": "$LOG_INGEST_JOURNAL_PATH",
    "logIngestRetentionBytes": 104857600,
    "logIngestDropPolicy": "drop-oldest"
  }
}
JSON
  log "wrote broker config to $BROKER_CONFIG with LogIngest journal $LOG_INGEST_JOURNAL_PATH"
}

write_task_json() {
  rm -f "$MARKER_FILE"
  cat >"$TASK_TOML" <<TOML
schemaVersion = "task-schedule/v2"
name = "TP-005 smoke run $RUN_ID"
description = "Fresh TaskSchedule smoke task generated by scripts/task-schedule-smoke.sh."
labels = ["smoke", "single-worker"]

[retry]
maxAttempts = 0
intervalSec = 0

[schedule]
priority = 50
requiredTags = []
preferredTags = []
maxRuntimeSec = $TASK_TIMEOUT_SEC

[[steps]]
name = "write-marker"

[steps.run]
type = "shell"
command = "sh"
args = ["-c", "mkdir -p '$EVIDENCE_DIR' && printf '%s\\n' '$RUN_ID' > '$MARKER_FILE' && printf '%s\\n' '$RUN_ID'"]
timeoutSec = $TASK_TIMEOUT_SEC

[[outputs]]
name = "marker"
kind = "file"
path = "$MARKER_FILE"
required = true

[[success.checks]]
name = "marker exists"
type = "path-exists"
path = "$MARKER_FILE"

[[success.checks]]
name = "marker non-empty"
type = "path-nonempty"
path = "$MARKER_FILE"
TOML
  log "wrote task TOML to $TASK_TOML"
}

run_client() {
  log "submitting task through ts-client"
  if have_cmd timeout; then
    timeout "$CLIENT_TIMEOUT_SEC" cabal run TaskSchedule:exe:ts-client -- "$CLIENT_CONFIG" "$TASK_TOML" >"$CLIENT_STDIO_LOG" 2>&1
  else
    cabal run TaskSchedule:exe:ts-client -- "$CLIENT_CONFIG" "$TASK_TOML" >"$CLIENT_STDIO_LOG" 2>&1
  fi
}

wait_for_marker() {
  local server_pid="$1"
  local worker_pid="$2"
  local deadline=$((SECONDS + MARKER_TIMEOUT_SEC))
  while [ "$SECONDS" -le "$deadline" ]; do
    ensure_alive "server" "$server_pid" "$SERVER_STDIO_LOG" || return 1
    ensure_alive "worker" "$worker_pid" "$WORKER_STDIO_LOG" || return 1
    if [ -f "$MARKER_FILE" ] && [ "$(cat "$MARKER_FILE")" = "$RUN_ID" ]; then
      log "fresh marker proof found at $MARKER_FILE"
      return 0
    fi
    sleep 1
  done
  log "marker proof timed out after ${MARKER_TIMEOUT_SEC}s"
  return 1
}

collect_log_extracts() {
  if [ -f logs/taskScheduleServer.log ]; then
    grep -F "$RUN_ID" logs/taskScheduleServer.log >"$EVIDENCE_DIR/taskScheduleServer-run.log" 2>/dev/null || true
  fi
  if [ -f logs/taskScheduleWorker.log ]; then
    grep -F "$RUN_ID" logs/taskScheduleWorker.log >"$EVIDENCE_DIR/taskScheduleWorker-run.log" 2>/dev/null || true
  fi
  if [ -f logs/taskScheduleClient.log ]; then
    grep -F "$RUN_ID" logs/taskScheduleClient.log >"$EVIDENCE_DIR/taskScheduleClient-run.log" 2>/dev/null || true
  fi
}

check_garbage_for_run() {
  local garbage_file="$EVIDENCE_DIR/final-garbage.json"
  if snapshot_endpoint "garbage" "$garbage_file"; then
    rm -f "$garbage_file.err"
    if grep -F "$RUN_ID" "$garbage_file" >/dev/null 2>&1; then
      log "garbage endpoint contains current run id"
      return 1
    fi
    return 0
  fi
  log "could not fetch final garbage snapshot"
  return 1
}

logs_worker_file_has_run() {
  local file="$1"
  grep -F "\"workerId\":\"$WORKER_ID\"" "$file" >/dev/null 2>&1 \
    && grep -F '"stream":"stdout"' "$file" >/dev/null 2>&1 \
    && grep -F '"stream":"result"' "$file" >/dev/null 2>&1 \
    && grep -F "$RUN_ID" "$file" >/dev/null 2>&1 \
    && grep -F "ExitSuccess" "$file" >/dev/null 2>&1
}

log_stats_are_clean() {
  local file="$1"
  grep -F '"droppedEvents":0' "$file" >/dev/null 2>&1 \
    && grep -F '"rejectedEvents":0' "$file" >/dev/null 2>&1 \
    && grep -F '"sequenceGaps":0' "$file" >/dev/null 2>&1 \
    && grep -F '"workers":1' "$file" >/dev/null 2>&1 \
    && grep -F "\"$WORKER_ID\"" "$file" >/dev/null 2>&1 \
    && ! grep -F '"runtimeQueueStats"' "$file" >/dev/null 2>&1 \
    && ! grep -F '"currentDepth"' "$file" >/dev/null 2>&1 \
    && ! grep -F 'broker.task.queue' "$file" >/dev/null 2>&1
}

wait_for_worker_logging() {
  local server_pid="$1"
  local worker_pid="$2"
  local worker_logs_file="$EVIDENCE_DIR/logging-worker-${WORKER_ID}.json"
  local stats_file="$EVIDENCE_DIR/logging-stats.json"
  local deadline=$((SECONDS + LOGGING_TIMEOUT_SEC))
  while [ "$SECONDS" -le "$deadline" ]; do
    ensure_alive "server" "$server_pid" "$SERVER_STDIO_LOG" || return 1
    ensure_alive "worker" "$worker_pid" "$WORKER_STDIO_LOG" || return 1
    if snapshot_endpoint "logs/worker/$WORKER_ID" "$worker_logs_file"; then
      rm -f "$worker_logs_file.err"
      if logs_worker_file_has_run "$worker_logs_file" \
        && snapshot_endpoint "logs/stats" "$stats_file"; then
        rm -f "$stats_file.err"
        if log_stats_are_clean "$stats_file"; then
          log "worker logging evidence found in /logs/worker/$WORKER_ID with clean LogIngest-only /logs/stats for run $RUN_ID"
          return 0
        fi
      fi
    fi
    sleep 1
  done
  log "worker logging evidence timed out after ${LOGGING_TIMEOUT_SEC}s"
  return 1
}

main() {
  log "TaskSchedule smoke run_id=$RUN_ID"
  log "evidence_dir=$EVIDENCE_DIR"
  require_prerequisites
  write_broker_config
  ensure_config_exists "$BROKER_CONFIG" "broker"
  ensure_config_exists "$WORKER_CONFIG" "worker"
  ensure_config_exists "$CLIENT_CONFIG" "client"
  ensure_no_existing_info_server
  write_task_json

  start_tracked "server" "$SERVER_STDIO_LOG" cabal run TaskSchedule:exe:ts-server -- "$BROKER_CONFIG"
  local server_pid="${PROCESS_PIDS[0]}"
  wait_for_server "$server_pid" || fail_hard "server did not become ready"

  start_tracked "worker" "$WORKER_STDIO_LOG" cabal run TaskSchedule:exe:ts-worker -- "$WORKER_CONFIG"
  local worker_pid="${PROCESS_PIDS[1]}"
  wait_for_worker "$server_pid" "$worker_pid" || fail_hard "worker did not register"
  wait_for_runtime_queue_stats "$server_pid" "$worker_pid" || fail_hard "/info did not expose runtimeQueueStats, workerLivenessMap, and workerReservationMap"
  snapshot_all "ready"

  CLIENT_EXIT=0
  run_client || CLIENT_EXIT=$?
  printf '%s\n' "$CLIENT_EXIT" >"$EVIDENCE_DIR/client-exit-code.txt"
  log "ts-client exit code: $CLIENT_EXIT"

  local marker_ok=0
  wait_for_marker "$server_pid" "$worker_pid" || marker_ok=1
  local logging_ok=0
  wait_for_worker_logging "$server_pid" "$worker_pid" || logging_ok=1
  snapshot_all "final"
  collect_log_extracts || true

  if [ "$marker_ok" -ne 0 ]; then
    fail_hard "worker marker proof missing or stale for run $RUN_ID"
  fi

  if [ "$logging_ok" -ne 0 ]; then
    fail_hard "worker logging evidence missing from /logs/worker/$WORKER_ID or /logs/stats for run $RUN_ID"
  fi

  if ! check_garbage_for_run; then
    fail_hard "current run appeared in garbage or garbage endpoint was unavailable"
  fi

  if [ "$CLIENT_EXIT" -eq 0 ]; then
    log "PASS: client received ACK, worker wrote fresh marker, /info exposed runtimeQueueStats/liveness/reservations, and worker logging reached LogIngest /logs"
    write_result "PASS" "$CLIENT_EXIT" "client ACK plus fresh marker proof plus /info runtimeQueueStats/workerLivenessMap/workerReservationMap plus LogIngest-only /logs worker/stdout/result/stats evidence"
    return 0
  fi

  fail_hard "ts-client exited $CLIENT_EXIT; see $CLIENT_STDIO_LOG"
}

main "$@"
