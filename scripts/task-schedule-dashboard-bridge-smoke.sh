#!/usr/bin/env bash
# Bounded dashboard-facing submit smoke for TaskSchedule.
# Starts bridge + dashboard first to capture timeout/validation responses, then
# starts server + worker and submits a TOML task through the dashboard dev proxy.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

RUN_ID="${SMOKE_RUN_ID:-client-bridge-dashboard-smoke-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
EVIDENCE_ROOT="${SMOKE_EVIDENCE_ROOT:-.tmp/client-bridge-dashboard-smoke}"
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
TASK_TOML="$EVIDENCE_DIR/dashboard-bridge-task.toml"
MARKER_FILE="$EVIDENCE_DIR/dashboard-bridge-marker.txt"
BROWSER_MARKER_FILE="$EVIDENCE_DIR/browser-click-marker.txt"
BROWSER_TASK_NAME="dashboard browser click smoke $RUN_ID"
INFO_BASE="${SMOKE_INFO_BASE:-http://127.0.0.1:8081/SimpleServer}"
DASHBOARD_BASE="${SMOKE_DASHBOARD_BASE:-http://127.0.0.1:5173}"
SUBMIT_URL="$DASHBOARD_BASE/submit"
WORKER_ID="${SMOKE_WORKER_ID:-dashboardSmokeWorker_1}"
SERVER_READY_TIMEOUT_SEC="${SMOKE_SERVER_READY_TIMEOUT_SEC:-120}"
WORKER_READY_TIMEOUT_SEC="${SMOKE_WORKER_READY_TIMEOUT_SEC:-120}"
DASHBOARD_READY_TIMEOUT_SEC="${SMOKE_DASHBOARD_READY_TIMEOUT_SEC:-60}"
BRIDGE_READY_TIMEOUT_SEC="${SMOKE_BRIDGE_READY_TIMEOUT_SEC:-60}"
MARKER_TIMEOUT_SEC="${SMOKE_MARKER_TIMEOUT_SEC:-40}"
OBSERVE_TIMEOUT_SEC="${SMOKE_OBSERVE_TIMEOUT_SEC:-25}"

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
  local detail="${2:-}"
  {
    printf 'status=%s\n' "$status"
    printf 'run_id=%s\n' "$RUN_ID"
    printf 'evidence_dir=%s\n' "$EVIDENCE_DIR"
    printf 'branch=%s\n' "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    printf 'commit=%s\n' "$(git rev-parse HEAD 2>/dev/null || true)"
    printf 'submit_url=%s\n' "$SUBMIT_URL"
    printf 'marker_file=%s\n' "$MARKER_FILE"
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
    log "smoke exiting with status $status; evidence preserved at $EVIDENCE_DIR"
  else
    log "smoke complete; evidence preserved at $EVIDENCE_DIR"
  fi
  exit "$status"
}

trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail_hard() {
  local message="$1"
  log "FAIL: $message"
  snapshot_all "failure" || true
  write_result "FAIL" "$message"
  exit 1
}

require_prerequisites() {
  local missing=0
  for cmd in cabal curl grep date mkdir cat printf sleep python3 npm git; do
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
}

ensure_no_existing_services() {
  if curl_local -fsS --max-time 1 "$INFO_BASE/info" >"$EVIDENCE_DIR/preexisting-info.json" 2>"$EVIDENCE_DIR/preexisting-info.err"; then
    fail_hard "info endpoint was already responding before smoke server start; stop it or override SMOKE_INFO_BASE"
  fi
  rm -f "$EVIDENCE_DIR/preexisting-info.json" "$EVIDENCE_DIR/preexisting-info.err"
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
  "taskProcessor": {"taskQueuePullNo": 10, "failedTaskQueuePullNo": 10, "triggerAlgoMaxNotifyCount": 10, "triggerAlgoMaxWaitSec": 10, "workerStaleTimeoutSec": 60},
  "infoStorage": {"httpPort": 8081, "logIngestDefaultAddr": "tcp://127.0.0.1:5557", "logIngestDefaultBufferSize": 1000, "infoFetchIntervalSec": 2},
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
  "workerDealerPairAddr": "inproc://TaskScheduleDashboardBridgeSmoke",
  "loadBalancerBackendAddr": "tcp://127.0.0.1:5556",
  "workerStatusReportIntervalSec": 1,
  "parallelTasksNo": 1,
  "workerTags": ["linux", "dashboard-smoke"],
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
  "bridgeMaxRequestBytes": 65536,
  "bridgeAllowedOrigins": [
    "http://127.0.0.1:5173",
    "http://localhost:5173",
    "http://127.0.0.1:4173",
    "http://localhost:4173"
  ],
  "bridgeAllowNoOrigin": true,
  "bridgeClient": {
    "clientId": "dashboardSmokeBridge_1",
    "loadBalancerFrontendAddr": "tcp://127.0.0.1:5555",
    "reqTimeoutSec": 1
  }
}
JSON

  cat >"$TASK_TOML" <<TOML
schemaVersion = "task-schedule/v2"
name = "dashboard bridge smoke marker"
description = "Submitted through the dashboard dev proxy to the TaskSchedule client bridge."
labels = ["dashboard", "bridge", "smoke"]

[retry]
maxAttempts = 0
intervalSec = 0

[schedule]
priority = 50
requiredTags = []
preferredTags = []
maxRuntimeSec = 25

[[steps]]
name = "write-dashboard-bridge-marker"

[steps.run]
type = "shell"
command = "sh"
args = ["-c", "sleep 12; mkdir -p '$EVIDENCE_DIR'; printf 'dashboard-bridge-ok\\n' > '$MARKER_FILE'"]
timeoutSec = 20

[[outputs]]
name = "dashboard bridge marker"
kind = "file"
path = "$MARKER_FILE"
required = true

[[success.checks]]
name = "dashboard bridge marker exists"
type = "path-exists"
path = "$MARKER_FILE"

[[success.checks]]
name = "dashboard bridge marker non-empty"
type = "path-nonempty"
path = "$MARKER_FILE"
TOML
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
  local server_pid="$1"
  local worker_pid="$2"
  local deadline=$((SECONDS + OBSERVE_TIMEOUT_SEC))
  while [ "$SECONDS" -le "$deadline" ]; do
    ensure_alive "server" "$server_pid" "$SERVER_STDIO_LOG" || return 1
    ensure_alive "worker" "$worker_pid" "$WORKER_STDIO_LOG" || return 1
    snapshot_endpoint "worker_tasks" "$EVIDENCE_DIR/during-worker_tasks.json" || true
    snapshot_endpoint "tasks" "$EVIDENCE_DIR/during-tasks.json" || true
    if grep -F "dashboard bridge smoke marker" "$EVIDENCE_DIR/during-worker_tasks.json" "$EVIDENCE_DIR/during-tasks.json" >/dev/null 2>&1; then
      log "submitted task is observable through dashboard-polled task endpoints"
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_marker_file() {
  local server_pid="$1"
  local worker_pid="$2"
  local marker_file="$3"
  local expected="$4"
  local label="$5"
  local deadline=$((SECONDS + MARKER_TIMEOUT_SEC))
  while [ "$SECONDS" -le "$deadline" ]; do
    ensure_alive "server" "$server_pid" "$SERVER_STDIO_LOG" || return 1
    ensure_alive "worker" "$worker_pid" "$WORKER_STDIO_LOG" || return 1
    if [ -f "$marker_file" ] && grep -F "$expected" "$marker_file" >/dev/null 2>&1; then
      log "$label marker proof found at $marker_file"
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_marker() {
  wait_for_marker_file "$1" "$2" "$MARKER_FILE" "dashboard-bridge-ok" "worker"
}

assert_response_contains() {
  local response_file="$1"
  local expected="$2"
  if ! grep -F "$expected" "$response_file" >/dev/null 2>&1; then
    fail_hard "expected $response_file to contain: $expected"
  fi
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

main() {
  require_prerequisites
  ensure_no_existing_services
  write_configs
  write_result "RUNNING" "smoke started"

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

  make_submit_request "$TASK_TOML" "$EVIDENCE_DIR/submit-forbidden-origin-request.json"
  curl_local -sS -o "$EVIDENCE_DIR/submit-forbidden-origin-response.json" -w '%{http_code}' \
    -H 'Origin: https://example.invalid' \
    -H 'Accept: application/json' \
    -H 'Content-Type: application/json' \
    --data-binary "@$EVIDENCE_DIR/submit-forbidden-origin-request.json" \
    "http://127.0.0.1:8090/submit" >"$EVIDENCE_DIR/submit-forbidden-origin-status.txt" 2>"$EVIDENCE_DIR/submit-forbidden-origin-response.json.err"
  assert_status_code "$EVIDENCE_DIR/submit-forbidden-origin-status.txt" 403
  assert_response_contains "$EVIDENCE_DIR/submit-forbidden-origin-response.json" 'browser origin is not allowed'
  log "captured forbidden browser origin response on direct bridge endpoint"

  make_submit_request "$TASK_TOML" "$EVIDENCE_DIR/submit-timeout-request.json"
  post_json "$EVIDENCE_DIR/submit-timeout-request.json" "$EVIDENCE_DIR/submit-ack-timeout-response.json" "$EVIDENCE_DIR/submit-ack-timeout-status.txt"
  assert_status_code "$EVIDENCE_DIR/submit-ack-timeout-status.txt" 504
  assert_response_contains "$EVIDENCE_DIR/submit-ack-timeout-response.json" '"status":"ack-timeout"'
  log "captured ACK timeout response before broker startup"

  printf '{"format":"json","taskToml":"schemaVersion = \\\"task-schedule/v2\\\""}\n' >"$EVIDENCE_DIR/submit-unsupported-format-request.json"
  post_json "$EVIDENCE_DIR/submit-unsupported-format-request.json" "$EVIDENCE_DIR/submit-unsupported-format-response.json" "$EVIDENCE_DIR/submit-unsupported-format-status.txt"
  assert_status_code "$EVIDENCE_DIR/submit-unsupported-format-status.txt" 400
  assert_response_contains "$EVIDENCE_DIR/submit-unsupported-format-response.json" '"status":"unsupported-format"'

  printf '{"format":"toml","taskToml":"schemaVersion ="}\n' >"$EVIDENCE_DIR/submit-invalid-toml-request.json"
  post_json "$EVIDENCE_DIR/submit-invalid-toml-request.json" "$EVIDENCE_DIR/submit-invalid-toml-response.json" "$EVIDENCE_DIR/submit-invalid-toml-status.txt"
  assert_status_code "$EVIDENCE_DIR/submit-invalid-toml-status.txt" 400
  assert_response_contains "$EVIDENCE_DIR/submit-invalid-toml-response.json" '"status":"validation-error"'

  start_tracked "server" "$SERVER_STDIO_LOG" cabal run TaskSchedule:exe:ts-server -- "$BROKER_CONFIG"
  wait_for_server "${PROCESS_PIDS[2]}" || fail_hard "server did not become ready"
  start_tracked "worker" "$WORKER_STDIO_LOG" cabal run TaskSchedule:exe:ts-worker -- "$WORKER_CONFIG"
  wait_for_worker "${PROCESS_PIDS[2]}" "${PROCESS_PIDS[3]}" || fail_hard "worker did not become visible"

  make_submit_request "$TASK_TOML" "$EVIDENCE_DIR/submit-success-request.json"
  post_json "$EVIDENCE_DIR/submit-success-request.json" "$EVIDENCE_DIR/submit-success-response.json" "$EVIDENCE_DIR/submit-success-status.txt"
  assert_status_code "$EVIDENCE_DIR/submit-success-status.txt" 200
  assert_response_contains "$EVIDENCE_DIR/submit-success-response.json" '"status":"accepted"'
  assert_response_contains "$EVIDENCE_DIR/submit-success-response.json" 'accepted/enqueued'
  log "captured accepted/enqueued response through dashboard dev proxy"

  if [ "${SMOKE_BROWSER_CLICK:-0}" = "1" ]; then
    local browser_command
    browser_command="mkdir -p '$EVIDENCE_DIR'; printf 'dashboard-browser-click-ok\\n' > '$BROWSER_MARKER_FILE'"
    log "running browser click automation through the dashboard submit panel"
    DASHBOARD_BASE="$DASHBOARD_BASE" \
      EVIDENCE_DIR="$EVIDENCE_DIR" \
      BROWSER_SMOKE_TASK_NAME="$BROWSER_TASK_NAME" \
      BROWSER_SMOKE_MARKER_PATH="$BROWSER_MARKER_FILE" \
      BROWSER_SMOKE_COMMAND="$browser_command" \
      node scripts/dashboard-submit-browser-smoke.mjs || fail_hard "browser click dashboard submit smoke failed"
    assert_response_contains "$EVIDENCE_DIR/browser-submit-result.json" '"ok": true'
    log "captured accepted/enqueued response through browser click automation"
  fi

  wait_for_task_observation "${PROCESS_PIDS[2]}" "${PROCESS_PIDS[3]}" || fail_hard "submitted task did not appear in dashboard-polled task endpoints"
  wait_for_marker "${PROCESS_PIDS[2]}" "${PROCESS_PIDS[3]}" || fail_hard "worker marker proof was not written"
  if [ "${SMOKE_BROWSER_CLICK:-0}" = "1" ]; then
    wait_for_marker_file "${PROCESS_PIDS[2]}" "${PROCESS_PIDS[3]}" "$BROWSER_MARKER_FILE" "dashboard-browser-click-ok" "browser-click" || fail_hard "browser-click worker marker proof was not written"
  fi
  snapshot_all "after-submit"

  write_result "PASS" "dashboard proxy /submit accepted task and marker/log/status evidence was preserved"
  log "PASS: evidence preserved at $EVIDENCE_DIR"
}

main "$@"
