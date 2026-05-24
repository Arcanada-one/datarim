#!/usr/bin/env bash
# orchestrator-input-handler.sh — inbound command handler for dr-orchestrate.
#
# Three invocation modes (auto-detected from $1):
#
#   1. Named-arg (legacy CLI / test harness):
#        $1 starts with '-' (--body, --auth, --sync-timeout, -h).
#        Output: JSON event document to stdout, exit 0/1.
#
#   2. Uniform 4-arg (TUNE-0295 router):
#        $1 is HTTP method [A-Z], $2 is path, $3 is body-file, $4 is headers-file.
#        Output: handler-protocol envelope "<status>\r\n<headers>\r\n\r\n<body>".
#
#   3. Positional legacy (pre-TUNE-0295 third-party webhook bridge):
#        $1 is raw body, $2 is optional X-Sync-Timeout ms.
#        Output: JSON event document, exit 0/1. Auth pre-validated upstream.
#
# Sync shortcut: commands in SYNC_WHITELIST + X-Sync-Timeout <=2000ms
#   → executes inline and returns JSON result on stdout.
# Async path: enqueues body as inbox/<ulid>.json, exits 0 / status 202.

set -euo pipefail

: "${DR_ORCH_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${DR_ORCH_INBOX_DIR:=$HOME/.local/share/datarim-orchestrate/inbox}"
: "${DR_ORCH_INBOUND_TOKEN:=}"

# Whitelisted commands for sync shortcut (V-AC-5/6).
SYNC_WHITELIST=("dr-status" "dr-help")

_usage() {
  printf 'usage: orchestrator-input-handler.sh --body <json> --auth <token> [--sync-timeout <ms>]\n' >&2
  exit 2
}

_ulid_fallback() {
  printf '%s%s' "$(date -u +%Y%m%dT%H%M%S%3N 2>/dev/null || date -u +%Y%m%dT%H%M%S)" \
    "$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' || printf '%016x' $$)"
}

_is_whitelisted() {
  local cmd="$1" w
  for w in "${SYNC_WHITELIST[@]}"; do
    [[ "$cmd" == "$w" ]] && return 0
  done
  return 1
}

# Emit handler-protocol envelope: <status>\r\n<headers>\r\n\r\n<body>
_emit_envelope() {
  local status="$1" body="$2"
  printf '%s\r\nContent-Type: application/json\r\n\r\n%s' "$status" "$body"
}

# Detect mode from $1.
UNIFORM_MODE=0
LEGACY_NAMED=0
case "${1:-}" in
  -*)         LEGACY_NAMED=1 ;;
  [A-Z]*)     UNIFORM_MODE=1 ;;
  *)          : ;;  # legacy positional — implicit
esac

BODY=""
AUTH_TOKEN=""
SYNC_TIMEOUT_MS=0

if (( LEGACY_NAMED )); then
  while (( $# > 0 )); do
    case "$1" in
      --body)          BODY="$2";            shift 2 ;;
      --auth)          AUTH_TOKEN="$2";      shift 2 ;;
      --sync-timeout)  SYNC_TIMEOUT_MS="$2"; shift 2 ;;
      -h|--help)       _usage ;;
      *)               echo "ERR: unknown arg '$1'" >&2; exit 2 ;;
    esac
  done
elif (( UNIFORM_MODE )); then
  # $1=method, $2=path, $3=body-file, $4=headers-file.
  method="$1"
  path_="$2"
  body_file="${3:-}"
  hdrs_file="${4:-}"
  : "$method" "$path_"  # logged surfaces, currently unused beyond detection
  if [[ -f "$body_file" ]]; then BODY="$(cat "$body_file")"; fi
  if [[ -f "$hdrs_file" ]]; then
    # Parse X-Sync-Timeout header value (case-insensitive). `|| true` so
    # an empty/missing header does not trip set -e via pipefail.
    SYNC_TIMEOUT_MS="$( { grep -i '^X-Sync-Timeout:' "$hdrs_file" 2>/dev/null || true; } \
      | head -1 \
      | sed -E 's/^[^:]+:[[:space:]]*//; s/[[:space:]]*$//' )"
    [[ "$SYNC_TIMEOUT_MS" =~ ^[0-9]+$ ]] || SYNC_TIMEOUT_MS=0
  fi
  AUTH_TOKEN="__webhook_preauthd__"
else
  # Positional legacy: $1=body, $2=timeout.
  BODY="${1:-}"
  SYNC_TIMEOUT_MS="${2:-0}"
  AUTH_TOKEN="${DR_ORCH_INBOUND_TOKEN:-__webhook_preauthd__}"
fi

# Helper: in uniform mode emit envelope and exit; else echo+exit.
_fail() {
  local status="$1" reason="$2"
  if (( UNIFORM_MODE )); then
    _emit_envelope "$status" "$(printf '{"error":"%s","status":%s}' "$reason" "$status")"
    exit 0
  fi
  echo "ERR: $reason" >&2
  exit 1
}

# Auth check (named-arg mode only — webhook + uniform pre-validate).
if (( LEGACY_NAMED )); then
  if [[ -z "$AUTH_TOKEN" ]]; then _fail 401 "missing auth token"; fi
  if [[ -z "${DR_ORCH_INBOUND_TOKEN:-}" ]]; then _fail 500 "DR_ORCH_INBOUND_TOKEN not configured"; fi
  if [[ "$AUTH_TOKEN" != "$DR_ORCH_INBOUND_TOKEN" ]]; then _fail 403 "invalid auth token"; fi
fi

# Validate JSON body.
if ! printf '%s' "$BODY" | jq -e . >/dev/null 2>&1; then
  _fail 400 "invalid JSON body"
fi

SESSION_ID="$(printf '%s' "$BODY" | jq -r '.session_id // empty')"
COMMAND="$(printf '%s' "$BODY" | jq -r '.command // empty')"

[[ -n "$SESSION_ID" ]] || _fail 400 "session_id required"
[[ -n "$COMMAND" ]]    || _fail 400 "command required"

if ! printf '%s' "$SESSION_ID" | grep -qE '^[A-Za-z0-9_-]{8,64}$'; then
  _fail 400 "session_id pattern invalid"
fi

# Sync shortcut: whitelisted + timeout in (0, 2000].
if _is_whitelisted "$COMMAND" && (( SYNC_TIMEOUT_MS > 0 )) && (( SYNC_TIMEOUT_MS <= 2000 )); then
  cycle_id="$("$DR_ORCH_DIR/scripts/escalation_backend.sh" _cycle_id 2>/dev/null || _ulid_fallback)"
  ts="$(date -u +%FT%TZ)"
  result=""
  case "$COMMAND" in
    dr-status)
      result="$(bash "$DR_ORCH_DIR/scripts/cmd_run.sh" --dry-run 2>/dev/null | head -1 || true)"
      ;;
    dr-help)
      result="dr-orchestrate: run | unknown-prompt | dry-run"
      ;;
  esac
  result_json="$(jq -n -c \
    --argjson sv 2 \
    --arg et "complete" \
    --arg cid "$cycle_id" \
    --arg sid "$SESSION_ID" \
    --arg txt "${result:-ok}" \
    --arg ts_ "$ts" \
    '{schema_version:$sv, event_type:$et, cycle_id:$cid, session_id:$sid, text:$txt, ts:$ts_}')"
  if (( UNIFORM_MODE )); then
    _emit_envelope 200 "$result_json"
  else
    printf '%s' "$result_json"
  fi
  exit 0
fi

# Async path: enqueue.
mkdir -p "$DR_ORCH_INBOX_DIR"
ulid="$(_ulid_fallback)"
inbox_file="$DR_ORCH_INBOX_DIR/${ulid}.json"
printf '%s\n' "$BODY" >"$inbox_file"
if (( UNIFORM_MODE )); then
  _emit_envelope 202 "$(printf '{"status":"queued","ulid":"%s"}' "$ulid")"
fi
exit 0
