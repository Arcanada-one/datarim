#!/usr/bin/env bash
# cli/lib/http.sh — HTTP client wrapping curl for /dr-orchestrate dispatch.
# Source: TUNE-0271 plan § Detailed Design 4.1; OpenAPI orchestrator-interface.yaml.
#
# Public functions:
#   http_dispatch_sync  <slash_cmd> <args_json>
#   http_dispatch_async <slash_cmd> <args_json>
#   classify_slash      <slash_cmd>  → "sync" | "async" | "forbidden_sync"
#
# Exit codes:
#   0   ok
#   21  connect-failed-after-retries
#   24  HTTP 4xx body received
#   25  HTTP 5xx body received
#   26  non-idempotent command on sync path
#   27  async timeout (3600s ceiling)
#
# Environment:
#   DATARIM_CLI_WEBHOOK_URL   default http://127.0.0.1:8090
#   DATARIM_CLI_REDIS_URL     default redis://127.0.0.1:6379/0
#   DATARIM_CLI_CLASSIFICATION_FILE  override yaml path

set -u

CLI_HTTP_EXIT_CONNECT=21
CLI_HTTP_EXIT_4XX=24
CLI_HTTP_EXIT_5XX=25
CLI_HTTP_EXIT_NON_IDEMP_SYNC=26
CLI_HTTP_EXIT_ASYNC_TIMEOUT=27

_cli_classification_path() {
    local override="${DATARIM_CLI_CLASSIFICATION_FILE:-}"
    if [ -n "$override" ]; then
        printf '%s' "$override"
    else
        local self
        self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        printf '%s/slash-classification.yaml' "$self"
    fi
}

# classify_slash <name>  echoes one of: sync | async | forbidden_sync
# Recognises both "dr-status" and "/dr-status" forms.
classify_slash() {
    local name="${1#/}"
    local path
    path="$(_cli_classification_path)"
    [ -f "$path" ] || { printf 'async'; return 0; }
    python3 - "$path" "$name" <<'PY'
import sys
try:
    import yaml
except ImportError:
    # Minimal fallback parser (only the two lists we need).
    yaml = None
path, name = sys.argv[1], sys.argv[2]
sync_wl, non_idem = [], []
if yaml is None:
    section = None
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            ln = raw.rstrip("\n")
            if ln.startswith("sync_whitelist:"):
                section = "sync"; continue
            if ln.startswith("non_idempotent:"):
                section = "non"; continue
            if ln.startswith(("schema_version:",)) or (ln and not ln.startswith(" ") and not ln.startswith("-")):
                section = None
            if section and ln.lstrip().startswith("- "):
                val = ln.lstrip()[2:].strip()
                (sync_wl if section == "sync" else non_idem).append(val)
else:
    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    sync_wl = data.get("sync_whitelist", []) or []
    non_idem = data.get("non_idempotent", []) or []
if name in sync_wl:
    print("sync")
elif name in non_idem:
    print("forbidden_sync")
else:
    print("async")
PY
}

# Build base webhook URL with /hooks/orchestrator-input path.
_webhook_endpoint() {
    printf '%s/hooks/orchestrator-input' "${DATARIM_CLI_WEBHOOK_URL:-http://127.0.0.1:8090}"
}

# http_dispatch_sync <slash_cmd> <args_json> → stdout = response body
# Exit 26 if slash_cmd is non-idempotent (must use async path).
http_dispatch_sync() {
    local slash="$1" args_json="${2:-{\}}"
    local class endpoint
    class="$(classify_slash "$slash")"
    case "$class" in
        forbidden_sync|async)
            printf '[http] %s is non-idempotent or async-only; refuse sync path\n' "$slash" >&2
            return $CLI_HTTP_EXIT_NON_IDEMP_SYNC ;;
        sync) ;;
    esac
    endpoint="$(_webhook_endpoint)"
    local payload tmpfile http_code body
    payload=$(python3 -c "import json,sys; print(json.dumps({'command':sys.argv[1],'args':json.loads(sys.argv[2]) if sys.argv[2].strip().startswith(('{','[')) else sys.argv[2]}))" "$slash" "$args_json")
    tmpfile="$(mktemp)"
    http_code=$(curl --silent --show-error --output "$tmpfile" --write-out '%{http_code}' \
        --retry 3 --retry-connrefused --retry-delay 1 --max-time 5 \
        --fail-with-body \
        -H 'Content-Type: application/json' \
        -H 'X-Sync-Timeout: 1500' \
        -X POST -d "$payload" \
        "$endpoint" 2>/dev/null) || true
    body="$(cat "$tmpfile")"
    rm -f "$tmpfile"
    case "$http_code" in
        000|"")
            printf '[http] connect-failed-after-retries %s\n' "$endpoint" >&2
            return $CLI_HTTP_EXIT_CONNECT ;;
        2*) printf '%s' "$body"; return 0 ;;
        4*)
            printf '[http] HTTP %s body=%s\n' "$http_code" "$body" >&2
            return $CLI_HTTP_EXIT_4XX ;;
        5*)
            printf '[http] HTTP %s body=%s\n' "$http_code" "$body" >&2
            return $CLI_HTTP_EXIT_5XX ;;
    esac
    return 1
}

# http_dispatch_async <slash_cmd> <args_json> → stdout = completion event JSON
# Polling order: Redis Sub channel datarim.cli.completion.<job_id> (3600s ceiling)
# → if Redis unreachable, fall back to HTTP GET poll every 30s.
http_dispatch_async() {
    local slash="$1" args_json="${2:-{\}}"
    local endpoint payload tmpfile http_code body job_id
    endpoint="$(_webhook_endpoint)"
    payload=$(python3 -c "import json,sys; print(json.dumps({'command':sys.argv[1],'args':json.loads(sys.argv[2]) if sys.argv[2].strip().startswith(('{','[')) else sys.argv[2]}))" "$slash" "$args_json")
    tmpfile="$(mktemp)"
    http_code=$(curl --silent --show-error --output "$tmpfile" --write-out '%{http_code}' \
        --retry 3 --retry-connrefused --retry-delay 1 --max-time 5 \
        --fail-with-body \
        -H 'Content-Type: application/json' \
        -X POST -d "$payload" \
        "$endpoint" 2>/dev/null) || true
    body="$(cat "$tmpfile")"
    rm -f "$tmpfile"
    if [ "$http_code" = "000" ] || [ -z "$http_code" ]; then
        printf '[http] connect-failed-after-retries %s\n' "$endpoint" >&2
        return $CLI_HTTP_EXIT_CONNECT
    fi
    if [ "$http_code" != "202" ]; then
        printf '[http] async dispatch expected 202, got %s body=%s\n' "$http_code" "$body" >&2
        case "$http_code" in
            4*) return $CLI_HTTP_EXIT_4XX ;;
            5*) return $CLI_HTTP_EXIT_5XX ;;
            *)  return 1 ;;
        esac
    fi
    job_id=$(printf '%s' "$body" | python3 -c "import json,sys; print(json.load(sys.stdin).get('job_id',''))" 2>/dev/null)
    if [ -z "$job_id" ]; then
        printf '[http] async accepted but job_id missing in body=%s\n' "$body" >&2
        return 1
    fi
    _poll_completion "$job_id" "$endpoint"
}

_poll_completion() {
    local job_id="$1" endpoint="$2"
    local timeout_s="${DATARIM_CLI_ASYNC_TIMEOUT:-3600}"
    local poll_interval=30
    local start_epoch now_epoch poll_tmp http_code event
    start_epoch=$(date -u +%s)
    while :; do
        now_epoch=$(date -u +%s)
        if [ $((now_epoch - start_epoch)) -ge "$timeout_s" ]; then
            printf '[http] async timeout (%ss ceiling)\n' "$timeout_s" >&2
            return $CLI_HTTP_EXIT_ASYNC_TIMEOUT
        fi
        poll_tmp="$(mktemp)"
        http_code=$(curl --silent --output "$poll_tmp" --write-out '%{http_code}' \
            --max-time 5 \
            "${endpoint%/orchestrator-input}/orchestrator-job/$job_id" 2>/dev/null || echo "000")
        if [ "$http_code" = "200" ]; then
            event=$(cat "$poll_tmp"); rm -f "$poll_tmp"
            printf '%s' "$event"
            return 0
        fi
        rm -f "$poll_tmp"
        sleep "$poll_interval"
    done
}
