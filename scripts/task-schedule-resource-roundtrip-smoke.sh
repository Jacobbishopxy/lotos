#!/usr/bin/env bash
# Background end-to-end resource-load round trip for TaskSchedule.
#
# Starts all local roles (broker/server, worker, client bridge, dashboard dev
# proxy), submits CPU/RSS/combined TOML tasks through the dashboard-facing
# /submit path, waits for worker-produced JSON summaries, snapshots observer
# endpoints, and then cleans up tracked process groups.
#
# Defaults are intentionally safe. Increase SMOKE_RESOURCE_* knobs when you want
# a heavier manual load run.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

RUN_ID="${SMOKE_RUN_ID:-task-schedule-resource-roundtrip-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
EVIDENCE_ROOT="${SMOKE_EVIDENCE_ROOT:-.tmp/task-schedule-resource-roundtrip-smoke}"
EVIDENCE_DIR="${SMOKE_EVIDENCE_DIR:-$EVIDENCE_ROOT/$RUN_ID}"
RUN_LOG="$EVIDENCE_DIR/smoke.log"
RESULT_FILE="$EVIDENCE_DIR/result.env"
SERVER_STDIO_LOG="$EVIDENCE_DIR/server-stdio.log"
WORKER_STDIO_LOG="$EVIDENCE_DIR/worker-stdio.log"
BRIDGE_STDIO_LOG="$EVIDENCE_DIR/bridge-stdio.log"
DASHBOARD_STDIO_LOG="$EVIDENCE_DIR/dashboard-stdio.log"
BROKER_CONFIG="$EVIDENCE_DIR/broker.json"
WORKER_CONFIG="$EVIDENCE_DIR/worker.json"
BRIDGE_CONFIG="$EVIDENCE_DIR/client-bridge.json"
TASK_DIR="$EVIDENCE_DIR/tasks"
SUMMARY_DIR="$EVIDENCE_DIR/summaries"
REQUEST_DIR="$EVIDENCE_DIR/requests"
RESPONSE_DIR="$EVIDENCE_DIR/responses"

INFO_BASE="${SMOKE_INFO_BASE:-http://127.0.0.1:8081/SimpleServer}"
DASHBOARD_BASE="${SMOKE_DASHBOARD_BASE:-http://127.0.0.1:5173}"
SUBMIT_URL="$DASHBOARD_BASE/submit"
WORKER_ID="${SMOKE_WORKER_ID:-resourceRoundtripWorker_1}"
SERVER_READY_TIMEOUT_SEC="${SMOKE_SERVER_READY_TIMEOUT_SEC:-120}"
WORKER_READY_TIMEOUT_SEC="${SMOKE_WORKER_READY_TIMEOUT_SEC:-120}"
DASHBOARD_READY_TIMEOUT_SEC="${SMOKE_DASHBOARD_READY_TIMEOUT_SEC:-60}"
BRIDGE_READY_TIMEOUT_SEC="${SMOKE_BRIDGE_READY_TIMEOUT_SEC:-60}"
SUMMARY_TIMEOUT_SEC="${SMOKE_RESOURCE_SUMMARY_TIMEOUT_SEC:-120}"
OBSERVE_TIMEOUT_SEC="${SMOKE_OBSERVE_TIMEOUT_SEC:-45}"

RESOURCE_CPU_WORKERS="${SMOKE_RESOURCE_CPU_WORKERS:-1}"
RESOURCE_CPU_DURATION_SEC="${SMOKE_RESOURCE_CPU_DURATION_SEC:-4}"
RESOURCE_RSS_MB="${SMOKE_RESOURCE_RSS_MB:-32}"
RESOURCE_RSS_DURATION_SEC="${SMOKE_RESOURCE_RSS_DURATION_SEC:-4}"
RESOURCE_COMBINED_CPU_WORKERS="${SMOKE_RESOURCE_COMBINED_CPU_WORKERS:-2}"
RESOURCE_COMBINED_RSS_MB="${SMOKE_RESOURCE_COMBINED_RSS_MB:-64}"
RESOURCE_COMBINED_DURATION_SEC="${SMOKE_RESOURCE_COMBINED_DURATION_SEC:-5}"
RESOURCE_TIMEOUT_PADDING_SEC="${SMOKE_RESOURCE_TIMEOUT_PADDING_SEC:-25}"

PROCESS_NAMES=()
PROCESS_PIDS=()
PROCESS_TARGETS=()
TASK_NAMES=()
TASK_TOMLS=()
SUMMARY_FILES=()

mkdir -p "$EVIDENCE_DIR" "$TASK_DIR" "$SUMMARY_DIR" "$REQUEST_DIR" "$RESPONSE_DIR" logs
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
    printf 'submit_url=%s\n' "$SUBMIT_URL"
    printf 'worker_id=%s\n' "$WORKER_ID"
    printf 'cpu_workers=%s\n' "$RESOURCE_CPU_WORKERS"
    printf 'cpu_duration_sec=%s\n' "$RESOURCE_CPU_DURATION_SEC"
    printf 'rss_mb=%s\n' "$RESOURCE_RSS_MB"
    printf 'rss_duration_sec=%s\n' "$RESOURCE_RSS_DURATION_SEC"
    printf 'combined_cpu_workers=%s\n' "$RESOURCE_COMBINED_CPU_WORKERS"
    printf 'combined_rss_mb=%s\n' "$RESOURCE_COMBINED_RSS_MB"
    printf 'combined_duration_sec=%s\n' "$RESOURCE_COMBINED_DURATION_SEC"
    printf 'detail=%s\n' "$detail"
  } >"$RESULT_FILE"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

curl_local() {
  curl --noproxy '*' "$@"
}

cleanup_processes() {
  local idx name pid target waited
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
    waited=0
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
    log "resource roundtrip smoke exiting with status $status; evidence preserved at $EVIDENCE_DIR"
  else
    log "resource roundtrip smoke complete; evidence preserved at $EVIDENCE_DIR"
  fi
  exit "$status"
}

trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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

fail_hard() {
  local message="$1"
  log "FAIL: $message"
  snapshot_all "failure" || true
  write_result "FAIL" "$message"
  exit 1
}

require_non_negative_int() {
  local value="$1"
  local label="$2"
  case "$value" in
    ''|*[!0-9]*) fail_hard "$label must be a non-negative integer, got: $value" ;;
  esac
}

require_positive_int() {
  local value="$1"
  local label="$2"
  require_non_negative_int "$value" "$label"
  if [ "$value" -le 0 ]; then
    fail_hard "$label must be > 0, got: $value"
  fi
}

require_prerequisites() {
  local missing=0
  for cmd in cabal curl grep date mkdir cat printf sleep python3 npm git kill; do
    if ! have_cmd "$cmd"; then
      printf 'Missing required command: %s\n' "$cmd" >&2
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    exit 1
  fi
  if ! have_cmd setsid; then
    log "WARNING: setsid(1) not found; cleanup will target tracked PIDs instead of process groups."
  fi

  require_non_negative_int "$RESOURCE_CPU_WORKERS" "SMOKE_RESOURCE_CPU_WORKERS"
  require_positive_int "$RESOURCE_CPU_DURATION_SEC" "SMOKE_RESOURCE_CPU_DURATION_SEC"
  require_non_negative_int "$RESOURCE_RSS_MB" "SMOKE_RESOURCE_RSS_MB"
  require_positive_int "$RESOURCE_RSS_DURATION_SEC" "SMOKE_RESOURCE_RSS_DURATION_SEC"
  require_non_negative_int "$RESOURCE_COMBINED_CPU_WORKERS" "SMOKE_RESOURCE_COMBINED_CPU_WORKERS"
  require_non_negative_int "$RESOURCE_COMBINED_RSS_MB" "SMOKE_RESOURCE_COMBINED_RSS_MB"
  require_positive_int "$RESOURCE_COMBINED_DURATION_SEC" "SMOKE_RESOURCE_COMBINED_DURATION_SEC"
  require_positive_int "$RESOURCE_TIMEOUT_PADDING_SEC" "SMOKE_RESOURCE_TIMEOUT_PADDING_SEC"
}

ensure_no_existing_services() {
  if curl_local -fsS --max-time 1 "$INFO_BASE/info" >"$EVIDENCE_DIR/preexisting-info.json" 2>"$EVIDENCE_DIR/preexisting-info.err"; then
    fail_hard "info endpoint was already responding before smoke server start; stop it or override SMOKE_INFO_BASE"
  fi
  rm -f "$EVIDENCE_DIR/preexisting-info.json" "$EVIDENCE_DIR/preexisting-info.err"

  if curl_local -fsS --max-time 1 -X OPTIONS "http://127.0.0.1:8090/submit" >"$EVIDENCE_DIR/preexisting-bridge.out" 2>"$EVIDENCE_DIR/preexisting-bridge.err"; then
    fail_hard "client bridge endpoint was already responding before smoke start; stop it before running this self-contained smoke"
  fi
  rm -f "$EVIDENCE_DIR/preexisting-bridge.out" "$EVIDENCE_DIR/preexisting-bridge.err"

  if curl_local -fsS --max-time 1 "$DASHBOARD_BASE/" >"$EVIDENCE_DIR/preexisting-dashboard.html" 2>"$EVIDENCE_DIR/preexisting-dashboard.err"; then
    fail_hard "dashboard endpoint was already responding before smoke start; stop it before running this self-contained smoke"
  fi
  rm -f "$EVIDENCE_DIR/preexisting-dashboard.html" "$EVIDENCE_DIR/preexisting-dashboard.err"
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

write_configs() {
  cat >"$BROKER_CONFIG" <<JSON
{
  "taskScheduler": {"taskQueueHWM": 1000, "failedTaskQueueHWM": 1000, "garbageBinSize": 100},
  "socketLayer": {"frontendAddr": "tcp://127.0.0.1:5555", "backendAddr": "tcp://127.0.0.1:5556"},
  "taskProcessor": {"taskQueuePullNo": 10, "failedTaskQueuePullNo": 10, "triggerAlgoMaxNotifyCount": 1, "triggerAlgoMaxWaitSec": 1, "workerStaleTimeoutSec": 60},
  "infoStorage": {"httpHost": "127.0.0.1", "httpPort": 8081, "logIngestDefaultAddr": "tcp://127.0.0.1:5557", "logIngestDefaultBufferSize": 1000, "infoFetchIntervalSec": 1},
  "logIngest": {
    "logIngestAddr": "tcp://127.0.0.1:5558",
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
    "logIngestJournalPath": "$EVIDENCE_DIR/worker-logs.journal",
    "logIngestRetentionBytes": 104857600,
    "logIngestDropPolicy": "drop-oldest"
  }
}
JSON

  cat >"$WORKER_CONFIG" <<JSON
{
  "workerId": "$WORKER_ID",
  "workerDealerPairAddr": "inproc://TaskScheduleResourceRoundtripSmoke",
  "loadBalancerBackendAddr": "tcp://127.0.0.1:5556",
  "workerStatusReportIntervalSec": 1,
  "parallelTasksNo": 1,
  "workerTags": ["linux", "resource-roundtrip-smoke"],
  "workerLogging": {
    "logIngestAddr": "tcp://127.0.0.1:5558",
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
    "logIngestJournalPath": "$EVIDENCE_DIR/worker-logs.journal",
    "logIngestRetentionBytes": 104857600,
    "logIngestDropPolicy": "drop-oldest"
  }
}
JSON

  cat >"$BRIDGE_CONFIG" <<JSON
{
  "bridgeBindHost": "127.0.0.1",
  "bridgePort": 8090,
  "bridgeMaxRequestBytes": 131072,
  "bridgeAllowedOrigins": [
    "http://127.0.0.1:5173",
    "http://localhost:5173"
  ],
  "bridgeAllowNoOrigin": true,
  "bridgeClient": {
    "clientId": "resourceRoundtripBridge_1",
    "loadBalancerFrontendAddr": "tcp://127.0.0.1:5555",
    "reqTimeoutSec": 5
  }
}
JSON
}

write_resource_task() {
  local key="$1"
  local task_name="$2"
  local cpu_workers="$3"
  local mem_mb="$4"
  local duration_sec="$5"
  local timeout_sec=$((duration_sec + RESOURCE_TIMEOUT_PADDING_SEC))
  local toml_file="$TASK_DIR/$key.toml"
  local summary_file="$SUMMARY_DIR/$key-summary.json"
  local max_rss_mb="$mem_mb"
  if [ "$max_rss_mb" -lt 1 ]; then
    max_rss_mb=1
  fi

  cat >"$toml_file" <<TOML
schemaVersion = "task-schedule/v2"
name = "$task_name"
description = "Generated by $RUN_ID for a full broker/worker/bridge/dashboard resource round trip."
labels = ["smoke", "resource", "$key"]

[retry]
maxAttempts = 0
intervalSec = 0

[schedule]
priority = 50
requiredTags = []
preferredTags = []
maxRuntimeSec = $timeout_sec
maxCpuPercent = 100
maxRssMb = $max_rss_mb

[[steps]]
name = "burn-$key"

[steps.run]
type = "shell"
command = "python3"
args = [
  "$ROOT_DIR/scripts/task-schedule-resource-burner.py",
  "--duration-sec", "$duration_sec",
  "--cpu-workers", "$cpu_workers",
  "--mem-mb", "$mem_mb",
  "--max-rss-mb", "$max_rss_mb",
  "--output", "$summary_file"
]
timeoutSec = $timeout_sec

[[outputs]]
name = "$key summary"
kind = "file"
path = "$summary_file"
required = true

[[success.checks]]
name = "$key summary nonempty"
type = "path-nonempty"
path = "$summary_file"
TOML

  TASK_NAMES+=("$task_name")
  TASK_TOMLS+=("$toml_file")
  SUMMARY_FILES+=("$summary_file")
}

write_tasks() {
  write_resource_task "cpu" "resource roundtrip cpu $RUN_ID" "$RESOURCE_CPU_WORKERS" 0 "$RESOURCE_CPU_DURATION_SEC"
  write_resource_task "rss" "resource roundtrip rss $RUN_ID" 0 "$RESOURCE_RSS_MB" "$RESOURCE_RSS_DURATION_SEC"
  write_resource_task "cpu-rss" "resource roundtrip cpu-rss $RUN_ID" "$RESOURCE_COMBINED_CPU_WORKERS" "$RESOURCE_COMBINED_RSS_MB" "$RESOURCE_COMBINED_DURATION_SEC"
}

make_submit_request() {
  local toml_file="$1"
  local output_file="$2"
  python3 - "$toml_file" >"$output_file" <<'PY'
import json
import pathlib
import sys
print(json.dumps({"format": "toml", "taskToml": pathlib.Path(sys.argv[1]).read_text()}))
PY
}

post_json() {
  local request_file="$1"
  local response_file="$2"
  local code_file="$3"
  curl_local -sS -o "$response_file" -w '%{http_code}' \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    --data-binary "@$request_file" \
    "$SUBMIT_URL" >"$code_file" 2>"$response_file.err"
}

assert_status_code() {
  local code_file="$1"
  local expected="$2"
  local actual
  actual="$(cat "$code_file" 2>/dev/null || true)"
  if [ "$actual" != "$expected" ]; then
    fail_hard "expected $code_file HTTP status $expected, got ${actual:-<missing>}"
  fi
}

assert_response_contains() {
  local response_file="$1"
  local expected="$2"
  if ! grep -F "$expected" "$response_file" >/dev/null 2>&1; then
    fail_hard "expected $response_file to contain: $expected"
  fi
}

wait_for_bridge() {
  local bridge_pid="$1"
  local deadline=$((SECONDS + BRIDGE_READY_TIMEOUT_SEC))
  while [ "$SECONDS" -le "$deadline" ]; do
    ensure_alive "bridge" "$bridge_pid" "$BRIDGE_STDIO_LOG" || return 1
    if curl_local -fsS --max-time 2 -X OPTIONS "http://127.0.0.1:8090/submit" >"$EVIDENCE_DIR/bridge-options.out" 2>"$EVIDENCE_DIR/bridge-options.err"; then
      rm -f "$EVIDENCE_DIR/bridge-options.err"
      log "client bridge is ready at http://127.0.0.1:8090/submit"
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_dashboard() {
  local dashboard_pid="$1"
  local deadline=$((SECONDS + DASHBOARD_READY_TIMEOUT_SEC))
  while [ "$SECONDS" -le "$deadline" ]; do
    ensure_alive "dashboard" "$dashboard_pid" "$DASHBOARD_STDIO_LOG" || return 1
    if curl_local -fsS --max-time 2 "$DASHBOARD_BASE/" >"$EVIDENCE_DIR/dashboard-index.html" 2>"$EVIDENCE_DIR/dashboard-index.err"; then
      rm -f "$EVIDENCE_DIR/dashboard-index.err"
      log "dashboard dev server is ready at $DASHBOARD_BASE"
      return 0
    fi
    sleep 1
  done
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
      if grep -F "\"$WORKER_ID\"" "$EVIDENCE_DIR/worker-ready-worker_stats.json" >/dev/null 2>&1; then
        log "worker $WORKER_ID is visible in /worker_stats"
        return 0
      fi
    fi
    sleep 1
  done
  return 1
}

wait_for_task_observation() {
  local task_name="$1"
  local server_pid="$2"
  local worker_pid="$3"
  local deadline=$((SECONDS + OBSERVE_TIMEOUT_SEC))
  while [ "$SECONDS" -le "$deadline" ]; do
    ensure_alive "server" "$server_pid" "$SERVER_STDIO_LOG" || return 1
    ensure_alive "worker" "$worker_pid" "$WORKER_STDIO_LOG" || return 1
    snapshot_endpoint "worker_tasks" "$EVIDENCE_DIR/during-worker_tasks.json" || true
    snapshot_endpoint "tasks" "$EVIDENCE_DIR/during-tasks.json" || true
    if grep -F "$task_name" "$EVIDENCE_DIR/during-worker_tasks.json" "$EVIDENCE_DIR/during-tasks.json" >/dev/null 2>&1; then
      log "task observed through dashboard-polled endpoints: $task_name"
      return 0
    fi
    sleep 1
  done
  return 1
}

summary_completed() {
  local summary_file="$1"
  python3 - "$summary_file" <<'PY'
import json
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except Exception:
    raise SystemExit(1)
if data.get("status") != "completed":
    raise SystemExit(1)
if "elapsedSec" not in data or "allocatedMemMiB" not in data:
    raise SystemExit(1)
PY
}

wait_for_summary() {
  local label="$1"
  local summary_file="$2"
  local server_pid="$3"
  local worker_pid="$4"
  local deadline=$((SECONDS + SUMMARY_TIMEOUT_SEC))
  while [ "$SECONDS" -le "$deadline" ]; do
    ensure_alive "server" "$server_pid" "$SERVER_STDIO_LOG" || return 1
    ensure_alive "worker" "$worker_pid" "$WORKER_STDIO_LOG" || return 1
    if [ -f "$summary_file" ] && summary_completed "$summary_file"; then
      log "$label resource summary completed at $summary_file"
      return 0
    fi
    sleep 1
  done
  return 1
}

submit_task() {
  local index="$1"
  local task_name="${TASK_NAMES[$index]}"
  local toml_file="${TASK_TOMLS[$index]}"
  local request_file="$REQUEST_DIR/$index-submit-request.json"
  local response_file="$RESPONSE_DIR/$index-submit-response.json"
  local code_file="$RESPONSE_DIR/$index-submit-status.txt"

  make_submit_request "$toml_file" "$request_file"
  post_json "$request_file" "$response_file" "$code_file"
  assert_status_code "$code_file" 200
  assert_response_contains "$response_file" '"status":"accepted"'
  assert_response_contains "$response_file" 'accepted/enqueued'
  log "accepted/enqueued via dashboard proxy: $task_name"
}

main() {
  require_prerequisites
  ensure_no_existing_services
  write_configs
  write_tasks
  write_result "RUNNING" "resource roundtrip smoke started"

  start_tracked "bridge" "$BRIDGE_STDIO_LOG" cabal run TaskSchedule:exe:ts-client-bridge -- "$BRIDGE_CONFIG"
  start_tracked "dashboard" "$DASHBOARD_STDIO_LOG" env \
    DASHBOARD_HOST=127.0.0.1 \
    DASHBOARD_API_TARGET=http://127.0.0.1:8081 \
    DASHBOARD_BRIDGE_TARGET=http://127.0.0.1:8090 \
    VITE_TASKSCHEDULE_API_TARGET=http://127.0.0.1:8081 \
    VITE_TASKSCHEDULE_API_ROOT=/SimpleServer \
    VITE_TASKSCHEDULE_BRIDGE_PATH=/submit \
    npm --prefix applications/dashboard run dev -- --host 127.0.0.1 --port 5173 --strictPort
  wait_for_bridge "${PROCESS_PIDS[0]}" || fail_hard "client bridge did not become ready"
  wait_for_dashboard "${PROCESS_PIDS[1]}" || fail_hard "dashboard dev server did not become ready"

  start_tracked "server" "$SERVER_STDIO_LOG" cabal run TaskSchedule:exe:ts-server -- "$BROKER_CONFIG"
  wait_for_server "${PROCESS_PIDS[2]}" || fail_hard "server did not become ready"
  start_tracked "worker" "$WORKER_STDIO_LOG" cabal run TaskSchedule:exe:ts-worker -- "$WORKER_CONFIG"
  wait_for_worker "${PROCESS_PIDS[2]}" "${PROCESS_PIDS[3]}" || fail_hard "worker did not become visible"

  snapshot_all "before-submit"

  submit_task 0
  wait_for_task_observation "${TASK_NAMES[0]}" "${PROCESS_PIDS[2]}" "${PROCESS_PIDS[3]}" || fail_hard "CPU task did not appear in task endpoints"
  submit_task 1
  submit_task 2

  wait_for_summary "cpu" "${SUMMARY_FILES[0]}" "${PROCESS_PIDS[2]}" "${PROCESS_PIDS[3]}" || fail_hard "CPU resource summary did not complete"
  wait_for_summary "rss" "${SUMMARY_FILES[1]}" "${PROCESS_PIDS[2]}" "${PROCESS_PIDS[3]}" || fail_hard "RSS resource summary did not complete"
  wait_for_summary "cpu-rss" "${SUMMARY_FILES[2]}" "${PROCESS_PIDS[2]}" "${PROCESS_PIDS[3]}" || fail_hard "combined CPU/RSS resource summary did not complete"

  snapshot_all "after-resource-roundtrip"
  write_result "PASS" "all roles started in background, dashboard proxy accepted three resource tasks, and worker summaries completed"
  log "PASS: evidence preserved at $EVIDENCE_DIR"
}

main "$@"
