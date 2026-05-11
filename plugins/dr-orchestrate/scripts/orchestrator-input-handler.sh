#!/usr/bin/env bash
# orchestrator-input-handler.sh — inbound command handler for dr-orchestrate.
# Accepts commands from bot clients via adnanh/webhook or direct CLI invocation.
#
# Usage (CLI / test harness):
#   orchestrator-input-handler.sh --body <json> --auth <token> [--sync-timeout <ms>]
#
# Usage (webhook invoke, positional):
#   orchestrator-input-handler.sh <raw_body> [x-sync-timeout]
#
# Auth: compares provided token against DR_ORCH_INBOUND_TOKEN.
# Sync shortcut: commands in SYNC_WHITELIST + X-Sync-Timeout ≤2000ms
#   → executes inline and returns JSON result on stdout.
# Async path: enqueues body as inbox/<ulid>.json, exits 0.
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

# _ulid_fallback — deterministic-enough id without external deps.
_ulid_fallback() {
  printf '%s%s' "$(date -u +%Y%m%dT%H%M%S%3N)" "$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' || printf '%016x' $$)"
}

# _is_whitelisted <command> → exits 0 if whitelisted
_is_whitelisted() {
  local cmd="$1"
  local w
  for w in "${SYNC_WHITELIST[@]}"; do
    [[ "$cmd" == "$w" ]] && return 0
  done
  return 1
}

# Parse args — support both --flag style (tests) and positional (webhook).
BODY=""
AUTH_TOKEN=""
SYNC_TIMEOUT_MS=0

if [[ "${1:-}" == "--body" ]]; then
  # Named-arg mode (test harness).
  while (( $# > 0 )); do
    case "$1" in
      --body)          BODY="$2";           shift 2 ;;
      --auth)          AUTH_TOKEN="$2";     shift 2 ;;
      --sync-timeout)  SYNC_TIMEOUT_MS="$2"; shift 2 ;;
      -h|--help)       _usage ;;
      *)               echo "ERR: unknown arg '$1'" >&2; exit 2 ;;
    esac
  done
else
  # Positional mode (webhook passes: raw_body [x-sync-timeout]).
  BODY="${1:-}"
  SYNC_TIMEOUT_MS="${2:-0}"
  # In webhook mode, auth is checked via trigger-rule (already validated).
  # For CLI/test via positional, skip auth check (caller-controlled).
  AUTH_TOKEN="${DR_ORCH_INBOUND_TOKEN:-__webhook_preauthd__}"
fi

# Auth check (named-arg mode only — webhook pre-validates via trigger-rule).
if [[ "${1:-__already_parsed__}" != "__already_parsed__" ]] || [[ "$AUTH_TOKEN" != "__webhook_preauthd__" ]]; then
  if [[ -z "$AUTH_TOKEN" ]]; then
    echo "ERR: missing auth token" >&2
    exit 1
  fi
  if [[ -z "${DR_ORCH_INBOUND_TOKEN:-}" ]]; then
    echo "ERR: DR_ORCH_INBOUND_TOKEN not configured" >&2
    exit 1
  fi
  if [[ "$AUTH_TOKEN" != "$DR_ORCH_INBOUND_TOKEN" ]]; then
    echo "ERR: invalid auth token" >&2
    exit 1
  fi
fi

# Validate JSON body.
if ! printf '%s' "$BODY" | jq -e . >/dev/null 2>&1; then
  echo "ERR: invalid JSON body" >&2
  exit 1
fi

# Extract required fields.
SESSION_ID="$(printf '%s' "$BODY" | jq -r '.session_id // empty')"
COMMAND="$(printf '%s' "$BODY" | jq -r '.command // empty')"

if [[ -z "$SESSION_ID" ]]; then
  echo "ERR: session_id required" >&2
  exit 1
fi

if [[ -z "$COMMAND" ]]; then
  echo "ERR: command required" >&2
  exit 1
fi

# Validate session_id pattern.
if ! printf '%s' "$SESSION_ID" | grep -qE '^[A-Za-z0-9_-]{8,64}$'; then
  echo "ERR: session_id pattern invalid" >&2
  exit 1
fi

# Sync shortcut (V-AC-5/6): whitelisted command + timeout ≤2000ms.
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
  jq -n -c \
    --argjson sv 2 \
    --arg et "complete" \
    --arg cid "$cycle_id" \
    --arg sid "$SESSION_ID" \
    --arg txt "${result:-ok}" \
    --arg ts_ "$ts" \
    '{schema_version:$sv, event_type:$et, cycle_id:$cid, session_id:$sid, text:$txt, ts:$ts_}'
  exit 0
fi

# Async path: enqueue to inbox.
mkdir -p "$DR_ORCH_INBOX_DIR"
ulid="$(_ulid_fallback)"
inbox_file="$DR_ORCH_INBOX_DIR/${ulid}.json"
printf '%s\n' "$BODY" > "$inbox_file"
exit 0
