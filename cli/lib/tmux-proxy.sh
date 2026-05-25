#!/usr/bin/env bash
# cli/lib/tmux-proxy.sh — HTTP proxy для /hooks/tmux endpoint (Phase 4, TUNE-0268).
# Source: TUNE-0268 Phase 4 plan § D1-D6; creative-TUNE-0268-architecture-tmux-proxy-contract.md.
#
# Никаких прямых вызовов `tmux` бинарника. Все tmux операции идут через
# единственный typed endpoint `POST /hooks/tmux` с per-op JSON discriminator.
#
# Public API:
#   tmux_proxy_sync   <op> <params_json>   — sync POST → echoes body | exit code
#   tmux_proxy_async  <op> <params_json>   — async POST → polling → echoes final body
#   tmux_validate_cmd <cmd>                — full-match whitelist regex check
#   tmux_validate_pane <pane>              — regex ^%[0-9]+$ check
#   tmux_validate_lines <n>                — int range [1,1000] check
#
# Exit codes (re-exports lib/exit-codes.sh symbols):
#   21 HTTP_CONNECT_FAIL    27 ASYNC_TIMEOUT      31 NOT_FOUND
#   24 HTTP_4XX             32 INVALID_COMMAND    34 WORKSPACE_DISCIPLINE_VIOLATION
#   25 HTTP_5XX
#
# Env:
#   DATARIM_CLI_WEBHOOK_URL          default http://127.0.0.1:8090
#   DATARIM_CLI_TMUX_WHITELIST       override whitelist file path
#   DATARIM_CLI_ASYNC_TIMEOUT        async polling ceiling seconds (default 3600)
#   DATARIM_CLI_TMUX_POLL_INTERVAL   async polling interval seconds (default 30)

set -u

[[ -n "${_TMUX_PROXY_LOADED:-}" ]] && return 0
_TMUX_PROXY_LOADED=1

_TMUX_PROXY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=exit-codes.sh
. "$_TMUX_PROXY_DIR/exit-codes.sh"

# Build /hooks/tmux endpoint URL.
_tmux_endpoint() {
    printf '%s/hooks/tmux' "${DATARIM_CLI_WEBHOOK_URL:-http://127.0.0.1:8090}"
}

# Resolve whitelist file (env override → lib-bundled default).
_tmux_whitelist_path() {
    local override="${DATARIM_CLI_TMUX_WHITELIST:-}"
    if [ -n "$override" ]; then
        printf '%s' "$override"
    else
        printf '%s/tmux-command-whitelist.txt' "$_TMUX_PROXY_DIR"
    fi
}

# tmux_validate_cmd <cmd> → exit 0 if cmd matches any whitelist regex full-match.
# Whitelist entries are anchored regex (e.g. `^python3$`).
tmux_validate_cmd() {
    local cmd="${1-}"
    [ -n "$cmd" ] || return "$(exit_code_of INVALID_COMMAND)"
    local wl_path
    wl_path="$(_tmux_whitelist_path)"
    [ -f "$wl_path" ] || return "$(exit_code_of INVALID_COMMAND)"
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|'#'*) continue ;; esac
        if [[ "$cmd" =~ $line ]]; then
            return 0
        fi
    done < "$wl_path"
    return "$(exit_code_of INVALID_COMMAND)"
}

# tmux_validate_pane <pane> → exit 0 if pane id matches ^%[0-9]+$.
tmux_validate_pane() {
    local pane="${1-}"
    if [[ "$pane" =~ ^%[0-9]+$ ]]; then
        return 0
    fi
    return "$(exit_code_of NOT_FOUND)"
}

# tmux_validate_lines <n> → exit 0 if n is integer in [1,1000].
tmux_validate_lines() {
    local n="${1-}"
    case "$n" in
        ''|*[!0-9]*) return "$(exit_code_of INVALID_COMMAND)" ;;
    esac
    if [ "$n" -ge 1 ] && [ "$n" -le 1000 ]; then
        return 0
    fi
    return "$(exit_code_of INVALID_COMMAND)"
}

# Internal: build JSON payload for /hooks/tmux POST.
# Args: <op> <params_json>
_tmux_build_payload() {
    local op="$1" params="${2:-{\}}"
    local ts session_id
    ts="$(date -u +%FT%TZ)"
    session_id="${DATARIM_CLI_AGENT_ID:-unknown}"
    python3 - "$op" "$params" "$ts" "$session_id" <<'PY'
import json, sys
op, params, ts, session_id = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    params_obj = json.loads(params) if params.strip() else {}
except Exception:
    params_obj = {}
print(json.dumps({
    "op": op,
    "params": params_obj,
    "session_id": session_id,
    "ts": ts,
    "meta": {"client": "datarim-cli", "phase": "4"},
}))
PY
}

# Map http_code → exit code (HTTP_CONNECT_FAIL / HTTP_4XX / HTTP_5XX / NOT_FOUND).
_tmux_classify_http() {
    local code="${1-}"
    case "$code" in
        000|"") exit_code_of HTTP_CONNECT_FAIL ;;
        2*) printf '0' ;;
        404) exit_code_of NOT_FOUND ;;
        4*) exit_code_of HTTP_4XX ;;
        5*) exit_code_of HTTP_5XX ;;
        *)  printf '1' ;;
    esac
}

# tmux_proxy_sync <op> <params_json> → stdout = response body; exit code per _tmux_classify_http.
tmux_proxy_sync() {
    local op="$1" params="${2:-{\}}"
    local endpoint payload tmpfile http_code body sync_timeout
    endpoint="$(_tmux_endpoint)"
    payload="$(_tmux_build_payload "$op" "$params")"
    case "$op" in
        list)        sync_timeout=1500 ;;
        read|attach|kill) sync_timeout=2000 ;;
        *)           sync_timeout=2000 ;;
    esac
    tmpfile="$(mktemp)"
    http_code=$(curl --silent --show-error --output "$tmpfile" --write-out '%{http_code}' \
        --retry 3 --retry-connrefused --retry-delay 1 --max-time 5 \
        --fail-with-body \
        -H 'Content-Type: application/json' \
        -H "X-Sync-Timeout: $sync_timeout" \
        -X POST -d "$payload" \
        "$endpoint" 2>/dev/null) || true
    body="$(cat "$tmpfile")"
    rm -f "$tmpfile"
    local mapped
    mapped="$(_tmux_classify_http "$http_code")"
    if [ "$mapped" = "0" ]; then
        printf '%s' "$body"
        return 0
    fi
    if [ -n "$body" ]; then
        printf '[tmux-proxy] HTTP %s body=%s\n' "$http_code" "$body" >&2
    else
        printf '[tmux-proxy] HTTP %s no-body\n' "$http_code" >&2
    fi
    return "$mapped"
}

# tmux_proxy_async <op> <params_json> → POST → 202 + job_id → poll → echoes final.
# Polling interval default 30s; ceiling DATARIM_CLI_ASYNC_TIMEOUT (default 3600).
tmux_proxy_async() {
    local op="$1" params="${2:-{\}}"
    local endpoint payload tmpfile http_code body job_id
    endpoint="$(_tmux_endpoint)"
    payload="$(_tmux_build_payload "$op" "$params")"
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
        printf '[tmux-proxy] connect-failed-after-retries %s\n' "$endpoint" >&2
        return "$(exit_code_of HTTP_CONNECT_FAIL)"
    fi
    if [ "$http_code" != "202" ]; then
        printf '[tmux-proxy] async expected 202, got %s body=%s\n' "$http_code" "$body" >&2
        local mapped
        mapped="$(_tmux_classify_http "$http_code")"
        [ "$mapped" = "0" ] && return 1
        return "$mapped"
    fi
    job_id=$(printf '%s' "$body" | python3 -c "import json,sys; print(json.load(sys.stdin).get('job_id',''))" 2>/dev/null)
    if [ -z "$job_id" ]; then
        printf '[tmux-proxy] async accepted but job_id missing in body=%s\n' "$body" >&2
        return 1
    fi
    _tmux_poll_job "$job_id"
}

# Internal: poll /hooks/tmux/job/<job_id> until 200 OR ceiling timeout.
_tmux_poll_job() {
    local job_id="$1"
    local timeout_s poll_interval start_epoch now_epoch poll_tmp http_code event
    timeout_s="${DATARIM_CLI_ASYNC_TIMEOUT:-3600}"
    poll_interval="${DATARIM_CLI_TMUX_POLL_INTERVAL:-30}"
    start_epoch=$(date -u +%s)
    while :; do
        now_epoch=$(date -u +%s)
        if [ $((now_epoch - start_epoch)) -ge "$timeout_s" ]; then
            printf '[tmux-proxy] async timeout (%ss ceiling)\n' "$timeout_s" >&2
            return "$(exit_code_of ASYNC_TIMEOUT)"
        fi
        poll_tmp="$(mktemp)"
        http_code=$(curl --silent --output "$poll_tmp" --write-out '%{http_code}' \
            --max-time 5 \
            "${DATARIM_CLI_WEBHOOK_URL:-http://127.0.0.1:8090}/hooks/tmux/job/$job_id" 2>/dev/null || echo "000")
        if [ "$http_code" = "200" ]; then
            event=$(cat "$poll_tmp"); rm -f "$poll_tmp"
            printf '%s' "$event"
            return 0
        fi
        rm -f "$poll_tmp"
        sleep "$poll_interval"
    done
}
