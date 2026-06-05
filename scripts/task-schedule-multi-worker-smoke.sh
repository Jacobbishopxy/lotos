#!/usr/bin/env bash
# Repeatable multi-worker end-to-end smoke path for the TaskSchedule demo.
#
# Exit codes:
#   0 - multi-worker pass: all clients ACK, all task markers are fresh,
#       at least two workers are registered, and each worker has current-run evidence
#       through stdio plus reliable /logs endpoints
#   1 - hard smoke failure, including readiness, ACK, scheduling evidence,
#       marker/logging, garbage, or cleanup-safety failures

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

RUN_ID="${SMOKE_RUN_ID:-task-schedule-multi-worker-smoke-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
EVIDENCE_ROOT="${SMOKE_EVIDENCE_ROOT:-.tmp/task-schedule-multi-worker-smoke}"
EVIDENCE_DIR="${SMOKE_EVIDENCE_DIR:-$EVIDENCE_ROOT/$RUN_ID}"
RUN_LOG="$EVIDENCE_DIR/smoke.log"
RESULT_FILE="$EVIDENCE_DIR/result.env"
BROKER_CONFIG="$EVIDENCE_DIR/broker.json"
MARKER_DIR="$EVIDENCE_DIR/markers"

INFO_BASE="${SMOKE_INFO_BASE:-http://127.0.0.1:8081/SimpleServer}"
WORKER_COUNT="${SMOKE_WORKER_COUNT:-2}"
TASK_COUNT="${SMOKE_TASK_COUNT:-4}"
WORKER_ID_PREFIX="${SMOKE_WORKER_ID_PREFIX:-smokeWorker_}"
CLIENT_ID_PREFIX="${SMOKE_CLIENT_ID_PREFIX:-smokeClient_}"
SERVER_READY_TIMEOUT_SEC="${SMOKE_SERVER_READY_TIMEOUT_SEC:-120}"
WORKER_READY_TIMEOUT_SEC="${SMOKE_WORKER_READY_TIMEOUT_SEC:-120}"
CLIENT_TIMEOUT_SEC="${SMOKE_CLIENT_TIMEOUT_SEC:-90}"
WORKER_EVIDENCE_TIMEOUT_SEC="${SMOKE_WORKER_EVIDENCE_TIMEOUT_SEC:-120}"
MARKER_TIMEOUT_SEC="${SMOKE_MARKER_TIMEOUT_SEC:-120}"
LOGGING_TIMEOUT_SEC="${SMOKE_LOGGING_TIMEOUT_SEC:-120}"
RUNTIME_STATS_TIMEOUT_SEC="${SMOKE_RUNTIME_STATS_TIMEOUT_SEC:-60}"
TASK_HOLD_SEC="${SMOKE_TASK_HOLD_SEC:-5}"
TASK_TIMEOUT_SEC="${SMOKE_TASK_TIMEOUT_SEC:-$((TASK_HOLD_SEC + 15))}"
BATCH_WINDOW_SEC="${SMOKE_BATCH_WINDOW_SEC:-45}"
TASK_PROCESSOR_NOTIFY_THRESHOLD="${SMOKE_TASK_PROCESSOR_NOTIFY_THRESHOLD:-100}"
INFO_FETCH_INTERVAL_SEC="${SMOKE_INFO_FETCH_INTERVAL_SEC:-5}"
WORKER_STATUS_INTERVAL_SEC="${SMOKE_WORKER_STATUS_INTERVAL_SEC:-2}"
WORKER_CAPACITY="${SMOKE_WORKER_CAPACITY:-1}"
LOG_INGEST_ADDR="${SMOKE_LOG_INGEST_ADDR:-tcp://127.0.0.1:5558}"
LOG_INGEST_JOURNAL_PATH="${SMOKE_LOG_INGEST_JOURNAL_PATH:-$EVIDENCE_DIR/worker-logs.journal}"

PROCESS_NAMES=()
PROCESS_PIDS=()
PROCESS_TARGETS=()
WORKER_IDS=()
WORKER_CONFIGS=()
WORKER_STDIO_LOGS=()
WORKER_PIDS=()
TASK_JSONS=()
MARKER_FILES=()
CLIENT_CONFIGS=()
CLIENT_STDIO_LOGS=()
CLIENT_PIDS=()
CLIENT_EXIT_FILES=()

mkdir -p "$EVIDENCE_DIR" "$MARKER_DIR" logs
: >"$RUN_LOG"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$RUN_LOG"
}

write_result() {
  local status="$1"
  local detail="${2:-}"
  {
    printf 'status=%s\n' "$status"
    printf 'run_id=%s\n' "$RUN_ID"
    printf 'evidence_dir=%s\n' "$EVIDENCE_DIR"
    printf 'worker_count=%s\n' "$WORKER_COUNT"
    printf 'task_count=%s\n' "$TASK_COUNT"
    printf 'worker_capacity=%s\n' "$WORKER_CAPACITY"
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
  write_result "FAIL" "$message"
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
    log "multi-worker smoke exiting with status $status; evidence preserved at $EVIDENCE_DIR"
  else
    log "multi-worker smoke complete; evidence preserved at $EVIDENCE_DIR"
  fi
  exit "$status"
}

trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

require_positive_int() {
  local value="$1"
  local label="$2"
  case "$value" in
    ''|*[!0-9]*) fail_hard "$label must be a positive integer, got: $value" ;;
  esac
  if [ "$value" -le 0 ]; then
    fail_hard "$label must be > 0, got: $value"
  fi
}

require_prerequisites() {
  local missing=0
  for cmd in cabal curl grep date mkdir cat printf sleep kill; do
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

  require_positive_int "$WORKER_COUNT" "SMOKE_WORKER_COUNT"
  require_positive_int "$TASK_COUNT" "SMOKE_TASK_COUNT"
  require_positive_int "$TASK_HOLD_SEC" "SMOKE_TASK_HOLD_SEC"
  require_positive_int "$TASK_TIMEOUT_SEC" "SMOKE_TASK_TIMEOUT_SEC"
  require_positive_int "$BATCH_WINDOW_SEC" "SMOKE_BATCH_WINDOW_SEC"
  require_positive_int "$WORKER_CAPACITY" "SMOKE_WORKER_CAPACITY"

  if [ "$WORKER_COUNT" -lt 2 ]; then
    fail_hard "multi-worker smoke requires at least 2 workers, got $WORKER_COUNT"
  fi
  if [ "$TASK_COUNT" -lt "$WORKER_COUNT" ]; then
    fail_hard "SMOKE_TASK_COUNT ($TASK_COUNT) must be >= SMOKE_WORKER_COUNT ($WORKER_COUNT)"
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
  local field queue_name wid
  grep -F '"runtimeQueueStats":[' "$file" >/dev/null 2>&1 || return 1
  for field in name currentDepth highWaterDepth totalEnqueued totalDrained warningThreshold; do
    grep -F "\"$field\"" "$file" >/dev/null 2>&1 || return 1
  done
  for queue_name in broker.task.queue broker.failed-task.queue broker.socketlayer.frontend-frames broker.socketlayer.backend-frames broker.socketlayer.taskprocessor-frames; do
    grep -F "\"name\":\"$queue_name\"" "$file" >/dev/null 2>&1 || return 1
  done
  grep -F '"workerLivenessMap":{' "$file" >/dev/null 2>&1 || return 1
  grep -F '"workerReservationMap":{' "$file" >/dev/null 2>&1 || return 1
  for field in lastSeen staleTimeoutSec heartbeatAgeSec stale; do
    grep -F "\"$field\"" "$file" >/dev/null 2>&1 || return 1
  done
  for wid in "${WORKER_IDS[@]}"; do
    grep -F "\"$wid\"" "$file" >/dev/null 2>&1 || return 1
  done
  return 0
}

wait_for_runtime_queue_stats() {
  local info_file="$EVIDENCE_DIR/runtime-queue-stats-info.json"
  local deadline=$((SECONDS + RUNTIME_STATS_TIMEOUT_SEC))
  while [ "$SECONDS" -le "$deadline" ]; do
    all_workers_alive || return 1
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

all_workers_alive() {
  local idx
  for ((idx=0; idx<${#WORKER_PIDS[@]}; idx++)); do
    ensure_alive "worker-${WORKER_IDS[$idx]}" "${WORKER_PIDS[$idx]}" "${WORKER_STDIO_LOGS[$idx]}" || return 1
  done
  return 0
}

wait_for_server() {
  local server_pid="$1"
  local server_log="$2"
  local deadline=$((SECONDS + SERVER_READY_TIMEOUT_SEC))
  while [ "$SECONDS" -le "$deadline" ]; do
    ensure_alive "server" "$server_pid" "$server_log" || return 1
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

worker_stats_contains_all_workers() {
  local file="$1"
  local wid
  for wid in "${WORKER_IDS[@]}"; do
    if ! grep -F "$wid" "$file" >/dev/null 2>&1; then
      return 1
    fi
  done
  return 0
}

wait_for_workers() {
  local server_pid="$1"
  local server_log="$2"
  local stats_file="$EVIDENCE_DIR/worker-ready-worker_stats.json"
  local deadline=$((SECONDS + WORKER_READY_TIMEOUT_SEC))
  while [ "$SECONDS" -le "$deadline" ]; do
    ensure_alive "server" "$server_pid" "$server_log" || return 1
    all_workers_alive || return 1
    if snapshot_endpoint "worker_stats" "$stats_file"; then
      rm -f "$stats_file.err"
      if worker_stats_contains_all_workers "$stats_file"; then
        log "all workers registered in /worker_stats: ${WORKER_IDS[*]}"
        return 0
      fi
    fi
    sleep 1
  done
  log "worker readiness timed out after ${WORKER_READY_TIMEOUT_SEC}s; expected workers: ${WORKER_IDS[*]}"
  return 1
}

write_broker_config() {
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
    "triggerAlgoMaxNotifyCount": $TASK_PROCESSOR_NOTIFY_THRESHOLD,
    "triggerAlgoMaxWaitSec": $BATCH_WINDOW_SEC,
    "workerStaleTimeoutSec": 60
  },
  "infoStorage": {
    "httpPort": 8081,
    "loggingAddr": "tcp://127.0.0.1:5557",
    "loggingsBufferSize": 1000,
    "infoFetchIntervalSec": $INFO_FETCH_INTERVAL_SEC
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
  log "wrote broker config to $BROKER_CONFIG with batch window ${BATCH_WINDOW_SEC}s and LogIngest journal $LOG_INGEST_JOURNAL_PATH"
}

write_worker_configs() {
  local idx wid config
  for ((idx=1; idx<=WORKER_COUNT; idx++)); do
    wid="${WORKER_ID_PREFIX}${idx}"
    config="$EVIDENCE_DIR/worker-${idx}.json"
    cat >"$config" <<JSON
{
  "workerId": "$wid",
  "workerDealerPairAddr": "inproc://TaskScheduleWorker-$idx",
  "loadBalancerBackendAddr": "tcp://127.0.0.1:5556",
  "loadBalancerLoggingAddr": "tcp://127.0.0.1:5557",
  "workerLogging": {
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
  },
  "workerStatusReportIntervalSec": $WORKER_STATUS_INTERVAL_SEC,
  "parallelTasksNo": $WORKER_CAPACITY
}
JSON
    WORKER_IDS+=("$wid")
    WORKER_CONFIGS+=("$config")
    WORKER_STDIO_LOGS+=("$EVIDENCE_DIR/worker-${idx}-stdio.log")
    log "wrote worker config for $wid to $config with capacity $WORKER_CAPACITY"
  done
}

write_client_configs_and_tasks() {
  local idx cid client_config task_json marker_file label
  for ((idx=1; idx<=TASK_COUNT; idx++)); do
    cid="${CLIENT_ID_PREFIX}${idx}"
    client_config="$EVIDENCE_DIR/client-${idx}.json"
    task_json="$EVIDENCE_DIR/task-${idx}.json"
    marker_file="$MARKER_DIR/task-${idx}.marker"
    label="$RUN_ID task-$idx"

    cat >"$client_config" <<JSON
{
  "clientId": "$cid",
  "loadBalancerFrontendAddr": "tcp://127.0.0.1:5555",
  "reqTimeoutSec": 10
}
JSON

    cat >"$task_json" <<JSON
{
  "taskID": null,
  "taskContent": "TP-017 multi-worker smoke $label",
  "taskRetry": 0,
  "taskRetryInterval": 0,
  "taskTimeout": $TASK_TIMEOUT_SEC,
  "taskProp": {
    "command": "mkdir -p '$MARKER_DIR' && printf '%s\\n' '$label START' && printf '%s\\n' '$label' > '$marker_file' && sleep '$TASK_HOLD_SEC' && printf '%s\\n' '$label DONE'",
    "executeTimeoutSec": $TASK_TIMEOUT_SEC
  }
}
JSON

    CLIENT_CONFIGS+=("$client_config")
    CLIENT_STDIO_LOGS+=("$EVIDENCE_DIR/client-${idx}-stdio.log")
    CLIENT_EXIT_FILES+=("$EVIDENCE_DIR/client-${idx}-exit-code.txt")
    TASK_JSONS+=("$task_json")
    MARKER_FILES+=("$marker_file")
    log "wrote client config $client_config and task JSON $task_json"
  done
}

start_server_and_workers() {
  local server_log="$EVIDENCE_DIR/server-stdio.log"
  start_tracked "server" "$server_log" cabal run TaskSchedule:exe:ts-server -- "$BROKER_CONFIG"
  local server_pid="${PROCESS_PIDS[0]}"
  wait_for_server "$server_pid" "$server_log" || fail_hard "server did not become ready"

  local idx
  for ((idx=0; idx<${#WORKER_CONFIGS[@]}; idx++)); do
    start_tracked "worker-${WORKER_IDS[$idx]}" "${WORKER_STDIO_LOGS[$idx]}" cabal run TaskSchedule:exe:ts-worker -- "${WORKER_CONFIGS[$idx]}"
    WORKER_PIDS+=("${PROCESS_PIDS[${#PROCESS_PIDS[@]} - 1]}")
  done

  wait_for_workers "$server_pid" "$server_log" || fail_hard "not all workers registered"
  wait_for_runtime_queue_stats || fail_hard "/info did not expose runtimeQueueStats, workerLivenessMap, and workerReservationMap"
  snapshot_all "ready"
}

submit_clients() {
  local idx pid
  log "submitting $TASK_COUNT tasks through distinct concurrent clients"
  for ((idx=0; idx<${#TASK_JSONS[@]}; idx++)); do
    if have_cmd timeout; then
      start_tracked "client-$((idx + 1))" "${CLIENT_STDIO_LOGS[$idx]}" timeout "$CLIENT_TIMEOUT_SEC" cabal run TaskSchedule:exe:ts-client -- "${CLIENT_CONFIGS[$idx]}" "${TASK_JSONS[$idx]}"
    else
      start_tracked "client-$((idx + 1))" "${CLIENT_STDIO_LOGS[$idx]}" cabal run TaskSchedule:exe:ts-client -- "${CLIENT_CONFIGS[$idx]}" "${TASK_JSONS[$idx]}"
    fi
    pid="${PROCESS_PIDS[${#PROCESS_PIDS[@]} - 1]}"
    CLIENT_PIDS+=("$pid")
  done
}

wait_for_clients() {
  local idx pid status failed=0
  for ((idx=0; idx<${#CLIENT_PIDS[@]}; idx++)); do
    pid="${CLIENT_PIDS[$idx]}"
    status=0
    wait "$pid" || status=$?
    printf '%s\n' "$status" >"${CLIENT_EXIT_FILES[$idx]}"
    log "client-$((idx + 1)) exit code: $status"
    if [ "$status" -ne 0 ]; then
      failed=1
    fi
  done
  if [ "$failed" -ne 0 ]; then
    return 1
  fi
  return 0
}

count_worker_current_tasks() {
  local file="$1"
  local wid="$2"
  local worker_slice
  worker_slice=$(tr -d '\n' <"$file" | sed -n "s/.*\"$wid\":\[\([^]]*\)\].*/\1/p")
  if [ -z "$worker_slice" ]; then
    printf '0\n'
    return 0
  fi
  printf '%s\n' "$worker_slice" | grep -o '"taskContent":"[^"]*"' | grep -F "$RUN_ID" | wc -l | tr -d ' '
  printf '\n'
}

worker_stats_have_configured_capacity() {
  local file="$1"
  local wid capacity_count
  for wid in "${WORKER_IDS[@]}"; do
    grep -F "\"$wid\"" "$file" >/dev/null 2>&1 || return 1
  done
  capacity_count=$(grep -o "\"taskCapacity\":$WORKER_CAPACITY" "$file" | wc -l | tr -d ' ')
  [ "$capacity_count" -ge "$WORKER_COUNT" ]
}

wait_for_capacity_reservation_snapshot() {
  local tasks_file="$EVIDENCE_DIR/capacity-worker_tasks.json"
  local stats_file="$EVIDENCE_DIR/capacity-worker_stats.json"
  local info_file="$EVIDENCE_DIR/capacity-info.json"
  local expected_inflight=$((TASK_COUNT < WORKER_COUNT * WORKER_CAPACITY ? TASK_COUNT : WORKER_COUNT * WORKER_CAPACITY))
  local deadline=$((SECONDS + WORKER_EVIDENCE_TIMEOUT_SEC))
  local wid count total over_capacity
  while [ "$SECONDS" -le "$deadline" ]; do
    all_workers_alive || return 1
    if snapshot_endpoint "worker_stats" "$stats_file" && snapshot_endpoint "worker_tasks" "$tasks_file" && snapshot_endpoint "info" "$info_file"; then
      rm -f "$stats_file.err" "$tasks_file.err" "$info_file.err"
      if worker_stats_have_configured_capacity "$stats_file" && grep -F '"workerReservationMap":{' "$info_file" >/dev/null 2>&1; then
        total=0
        over_capacity=0
        for wid in "${WORKER_IDS[@]}"; do
          count=$(count_worker_current_tasks "$tasks_file" "$wid")
          total=$((total + count))
          if [ "$count" -gt "$WORKER_CAPACITY" ]; then
            over_capacity=1
          fi
        done
        if [ "$total" -eq "$expected_inflight" ] && [ "$over_capacity" -eq 0 ]; then
          log "capacity/reservation snapshot valid: $total in-flight current-run tasks across ${#WORKER_IDS[@]} workers, capacity $WORKER_CAPACITY each"
          return 0
        fi
      fi
    fi
    sleep 1
  done
  log "capacity/reservation snapshot timed out after ${WORKER_EVIDENCE_TIMEOUT_SEC}s; expected in-flight current-run tasks=$expected_inflight capacity=$WORKER_CAPACITY"
  return 1
}

wait_for_worker_execution_evidence() {
  local deadline=$((SECONDS + WORKER_EVIDENCE_TIMEOUT_SEC))
  local idx all_found
  while [ "$SECONDS" -le "$deadline" ]; do
    all_workers_alive || return 1
    all_found=1
    for ((idx=0; idx<${#WORKER_STDIO_LOGS[@]}; idx++)); do
      if ! grep -F "$RUN_ID" "${WORKER_STDIO_LOGS[$idx]}" >/dev/null 2>&1; then
        all_found=0
      fi
    done
    if [ "$all_found" -eq 1 ]; then
      log "current-run task evidence found in every worker stdio log"
      return 0
    fi
    sleep 1
  done
  log "per-worker execution evidence timed out after ${WORKER_EVIDENCE_TIMEOUT_SEC}s"
  return 1
}

wait_for_markers() {
  local deadline=$((SECONDS + MARKER_TIMEOUT_SEC))
  local idx expected all_found
  while [ "$SECONDS" -le "$deadline" ]; do
    all_workers_alive || return 1
    all_found=1
    for ((idx=0; idx<${#MARKER_FILES[@]}; idx++)); do
      expected="$RUN_ID task-$((idx + 1))"
      if [ ! -f "${MARKER_FILES[$idx]}" ] || [ "$(cat "${MARKER_FILES[$idx]}")" != "$expected" ]; then
        all_found=0
      fi
    done
    if [ "$all_found" -eq 1 ]; then
      log "fresh marker proof found for all $TASK_COUNT tasks"
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
  local wid="$2"
  grep -F "\"workerId\":\"$wid\"" "$file" >/dev/null 2>&1 \
    && grep -F '"stream":"stdout"' "$file" >/dev/null 2>&1 \
    && grep -F '"stream":"result"' "$file" >/dev/null 2>&1 \
    && grep -F "$RUN_ID" "$file" >/dev/null 2>&1 \
    && grep -F "ExitSuccess" "$file" >/dev/null 2>&1
}

log_stats_are_clean() {
  local file="$1"
  local wid
  grep -F '"droppedEvents":0' "$file" >/dev/null 2>&1 \
    && grep -F '"rejectedEvents":0' "$file" >/dev/null 2>&1 \
    && grep -F '"sequenceGaps":0' "$file" >/dev/null 2>&1 \
    && grep -F "\"workers\":$WORKER_COUNT" "$file" >/dev/null 2>&1 \
    && grep -F "\"tasks\":$TASK_COUNT" "$file" >/dev/null 2>&1 \
    && ! grep -F '"runtimeQueueStats"' "$file" >/dev/null 2>&1 \
    && ! grep -F '"currentDepth"' "$file" >/dev/null 2>&1 \
    && ! grep -F 'broker.task.queue' "$file" >/dev/null 2>&1 || return 1
  for wid in "${WORKER_IDS[@]}"; do
    grep -F "\"$wid\"" "$file" >/dev/null 2>&1 || return 1
  done
  return 0
}

wait_for_worker_logging() {
  local stats_file="$EVIDENCE_DIR/logging-stats.json"
  local deadline=$((SECONDS + LOGGING_TIMEOUT_SEC))
  local wid worker_logs_file all_workers_logged
  while [ "$SECONDS" -le "$deadline" ]; do
    all_workers_alive || return 1
    all_workers_logged=1
    for wid in "${WORKER_IDS[@]}"; do
      worker_logs_file="$EVIDENCE_DIR/logging-worker-${wid}.json"
      if snapshot_endpoint "logs/worker/$wid" "$worker_logs_file"; then
        rm -f "$worker_logs_file.err"
        if ! logs_worker_file_has_run "$worker_logs_file" "$wid"; then
          all_workers_logged=0
        fi
      else
        all_workers_logged=0
      fi
    done
    if [ "$all_workers_logged" -eq 1 ] \
      && snapshot_endpoint "logs/stats" "$stats_file"; then
      rm -f "$stats_file.err"
      if log_stats_are_clean "$stats_file"; then
        log "worker logging evidence found in /logs/worker for all workers with clean LogIngest-only /logs/stats for run $RUN_ID"
        return 0
      fi
    fi
    sleep 1
  done
  log "worker logging evidence timed out after ${LOGGING_TIMEOUT_SEC}s"
  return 1
}

main() {
  log "TaskSchedule multi-worker smoke run_id=$RUN_ID"
  log "evidence_dir=$EVIDENCE_DIR"
  require_prerequisites
  ensure_no_existing_info_server
  write_broker_config
  write_worker_configs
  write_client_configs_and_tasks

  start_server_and_workers
  submit_clients
  wait_for_capacity_reservation_snapshot || fail_hard "capacity/reservation snapshot did not show configured-capacity-safe dispatch"
  wait_for_clients || fail_hard "one or more ts-client submissions failed; see client stdio logs"

  wait_for_worker_execution_evidence || fail_hard "not every worker processed current-run work"
  wait_for_markers || fail_hard "one or more task markers are missing or stale for run $RUN_ID"
  wait_for_worker_logging || fail_hard "worker logging evidence missing from /logs/worker/<workerId> or /logs/stats for run $RUN_ID"
  snapshot_all "final"
  collect_log_extracts || true

  if ! check_garbage_for_run; then
    fail_hard "current run appeared in garbage or garbage endpoint was unavailable"
  fi

  log "PASS: $TASK_COUNT tasks ACKed, ${#WORKER_IDS[@]} workers registered, capacity/reservations stayed within configured worker slots, all markers are fresh, /info exposed runtimeQueueStats/liveness/reservations, and worker logging reached LogIngest /logs"
  write_result "PASS" "multi-worker ACK plus per-worker execution evidence plus capacity/reservation snapshot plus fresh marker proof plus /info runtimeQueueStats/workerLivenessMap/workerReservationMap plus LogIngest-only /logs worker/stdout/result/stats evidence"
  return 0
}

main "$@"
