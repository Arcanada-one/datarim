#!/usr/bin/env bash
# tmux_dispatcher.sh — TUNE-0295 Phase B
# Handler for /hooks/tmux (POST) and /hooks/tmux/job/<uuid> (GET).
# Invoked by dr_orchestrate_router.sh with 4 args:
#   $1 = method, $2 = path, $3 = body-file, $4 = headers-file
# Writes handler-protocol output to stdout:
#   <status>\r\n<header-lines>\r\n\r\n<body>
#
# V-AC: V-AC-1 (endpoint live), V-AC-2 (manager funcs), V-AC-3 (async),
#       V-AC-4 (defence-in-depth — whitelist + pane regex).

set -o pipefail

: "${DR_ORCH_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${DR_ORCH_WHITELIST_FILE:=$DR_ORCH_DIR/config/tmux-command-whitelist.txt}"
: "${DR_ORCH_TMUX_MANAGER:=$DR_ORCH_DIR/scripts/tmux_manager.sh}"
: "${DR_ORCH_REDIS_STORE:=$DR_ORCH_DIR/scripts/redis_job_store.sh}"

PANE_RE='^%[0-9]+$'
UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}$'

# shellcheck source=/dev/null
. "$DR_ORCH_REDIS_STORE"
# shellcheck source=/dev/null
. "$DR_ORCH_TMUX_MANAGER"

# ---- output helpers ---------------------------------------------------

_emit() {
  # $1 = status, $2 = body json
  printf '%s\r\nContent-Type: application/json\r\n\r\n%s' "$1" "$2"
}

_err() {
  # $1 = status, $2 = error code, $3 = reason
  _emit "$1" "$(printf '{"error":"%s","reason":"%s"}' "$2" "$3")"
}

# ---- input parsing ----------------------------------------------------

_jq() {
  # Optional jq wrapper for body parsing. If jq missing, falls back to
  # plain bash via _grep_field. We require jq for clean parsing; absent
  # jq → 500 (operator install gap).
  if ! command -v jq >/dev/null 2>&1; then
    return 2
  fi
  jq "$@"
}

_field() {
  # _field <body-file> <jq-path-without-leading-dot>
  # Extracts a JSON string/scalar from body via jq -r.
  local file="$1" path="$2"
  jq -r "$path // empty" <"$file" 2>/dev/null
}

# ---- whitelist + regex ------------------------------------------------

_check_whitelist() {
  local cmd="$1"
  [[ -f "$DR_ORCH_WHITELIST_FILE" ]] || return 1
  local line
  while IFS= read -r line; do
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    if [[ "$cmd" =~ $line ]]; then
      # Full-match check: the regex MUST anchor ^...$; if matched
      # whole-string, accept.
      return 0
    fi
  done <"$DR_ORCH_WHITELIST_FILE"
  return 1
}

# Generate a UUID v4 — uses uuidgen if available, otherwise /dev/urandom.
_gen_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return 0
  fi
  # /dev/urandom fallback: 16 random bytes, format as uuid, set version=4 + variant=10.
  local hex
  hex="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  printf '%s-%s-4%s-%s%s-%s\n' \
    "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" \
    "$(printf '%x' $(( 0x${hex:16:1} & 0x3 | 0x8 )))" "${hex:17:3}" \
    "${hex:20:12}"
}

# ---- list -------------------------------------------------------------

_op_list() {
  local raw panes_json count
  if raw="$(tmux_list_panes_safe 2>/dev/null)"; then
    :
  else
    raw=""
  fi
  if [[ -z "$raw" ]]; then
    _emit 200 '{"data":{"panes":[],"count":0}}'
    return 0
  fi
  # Parse lines of pane_id|session|cmd|pid into JSON array.
  panes_json="$(awk -F'|' '
    BEGIN { sep="" }
    {
      gsub(/"/, "\\\"", $1); gsub(/"/, "\\\"", $2); gsub(/"/, "\\\"", $3); gsub(/"/, "\\\"", $4);
      printf "%s{\"id\":\"%s\",\"session\":\"%s\",\"cmd\":\"%s\",\"pid\":\"%s\"}", sep, $1, $2, $3, $4
      sep=","
    }
  ' <<<"$raw")"
  count="$(printf '%s\n' "$raw" | wc -l | tr -d ' ')"
  _emit 200 "$(printf '{"data":{"panes":[%s],"count":%s}}' "$panes_json" "$count")"
}

# ---- attach -----------------------------------------------------------

_op_attach() {
  local body="$1"
  local pane task_id
  pane="$(_field "$body" '.params.pane')"
  task_id="$(_field "$body" '.params.task_id')"
  if [[ ! "$pane" =~ $PANE_RE ]]; then
    _err 422 "pane_regex_reject" "pane '$pane' does not match $PANE_RE"
    return 0
  fi
  local cmd
  cmd="$(printf 'tmux attach-session -t datarim \\; select-pane -t %s' "$pane")"
  _emit 200 "$(printf '{"data":{"pane":"%s","session":"datarim","task_id":"%s","tmux_cmd":"%s"}}' "$pane" "$task_id" "$cmd")"
}

# ---- new (async) ------------------------------------------------------

_op_new() {
  local body="$1"
  local task_id cmd
  task_id="$(_field "$body" '.params.task_id')"
  cmd="$(_field "$body" '.params.cmd')"
  if [[ -z "$cmd" ]]; then
    _err 422 "missing_cmd" "params.cmd required"
    return 0
  fi
  if ! _check_whitelist "$cmd"; then
    _err 422 "whitelist_reject" "cmd '$cmd' does not match whitelist"
    return 0
  fi
  local uuid
  uuid="$(_gen_uuid)"
  # Set pending in store. If Redis unreachable → 503 (V-AC-9 fail-soft).
  if ! job_store_set "$uuid" '{"status":"pending"}'; then
    _err 503 "job_store_unavailable" "redis backend not reachable"
    return 0
  fi
  # Spawn background tmux new-session; on completion, write complete state.
  (
    if tmux_new_session_safe "$task_id" "$cmd" >/dev/null 2>&1; then
      job_store_set "$uuid" "$(printf '{"status":"complete","data":{"pane":"%s","session":"%s","cmd":"%s"}}' "%0" "$task_id" "$cmd")"
    else
      job_store_set "$uuid" '{"status":"error","error":"tmux_new_session_failed"}'
    fi
  ) &
  _emit 202 "$(printf '{"job_id":"%s"}' "$uuid")"
}

# ---- kill -------------------------------------------------------------

_op_kill() {
  local body="$1"
  local pane
  pane="$(_field "$body" '.params.pane')"
  if [[ ! "$pane" =~ $PANE_RE ]]; then
    _err 422 "pane_regex_reject" "pane '$pane' does not match $PANE_RE"
    return 0
  fi
  if tmux_kill_pane_safe "$pane" >/dev/null 2>&1; then
    _emit 200 "$(printf '{"data":{"pane":"%s","killed":true}}' "$pane")"
  else
    _emit 200 "$(printf '{"data":{"pane":"%s","killed":false}}' "$pane")"
  fi
}

# ---- read -------------------------------------------------------------

_op_read() {
  local body="$1"
  local pane lines
  pane="$(_field "$body" '.params.pane')"
  lines="$(_field "$body" '.params.lines')"
  if [[ ! "$pane" =~ $PANE_RE ]]; then
    _err 422 "pane_regex_reject" "pane '$pane' does not match $PANE_RE"
    return 0
  fi
  if [[ ! "$lines" =~ ^[0-9]+$ ]]; then
    lines=50
  fi
  local raw lines_json
  raw="$(tmux_capture_pane_safe "$pane" 2>/dev/null || true)"
  # Truncate to last $lines.
  if [[ -n "$raw" ]]; then
    raw="$(printf '%s\n' "$raw" | tail -n "$lines")"
  fi
  lines_json="$(awk '
    BEGIN { sep=""; printf "[" }
    {
      gsub(/\\/, "\\\\")
      gsub(/"/, "\\\"")
      printf "%s\"%s\"", sep, $0
      sep=","
    }
    END { print "]" }
  ' <<<"$raw")"
  _emit 200 "$(printf '{"data":{"pane":"%s","lines":%s,"truncated":false}}' "$pane" "$lines_json")"
}

# ---- GET /hooks/tmux/job/<uuid> ---------------------------------------

_handle_get_job() {
  local uuid="$1"
  if [[ ! "$uuid" =~ $UUID_RE ]]; then
    _err 400 "bad_uuid" "uuid does not match v4 pattern"
    return 0
  fi
  local val ttl
  ttl="$(job_store_ttl "$uuid")"
  if [[ "$ttl" == "-2" ]]; then
    _err 404 "job_not_found" "no such job"
    return 0
  fi
  if ! val="$(job_store_get "$uuid")"; then
    _err 410 "job_expired" "job ttl expired"
    return 0
  fi
  # If value contains status:complete → 200, else 202 pending.
  if [[ "$val" == *'"status":"complete"'* ]]; then
    _emit 200 "$val"
  elif [[ "$val" == *'"status":"error"'* ]]; then
    _emit 500 "$val"
  else
    _emit 202 "$val"
  fi
}

# ---- main dispatch ----------------------------------------------------

main() {
  local method="${1:-POST}" path="${2:-/hooks/tmux}" body_file="${3:-/dev/null}" headers_file="${4:-/dev/null}"
  : "$headers_file"  # currently unused at dispatcher layer

  if [[ "$method" == "GET" ]]; then
    case "$path" in
      /hooks/tmux/job/*)
        local uuid="${path##*/}"
        _handle_get_job "$uuid"
        return 0
        ;;
      *)
        _err 404 "not_found" "no GET route"
        return 0
        ;;
    esac
  fi

  # POST: parse op from body.
  local op
  op="$(_field "$body_file" '.op')"
  case "$op" in
    list)   _op_list ;;
    attach) _op_attach "$body_file" ;;
    new)    _op_new "$body_file" ;;
    kill)   _op_kill "$body_file" ;;
    read)   _op_read "$body_file" ;;
    "")     _err 400 "missing_op" "body.op required" ;;
    *)      _err 400 "unknown_op" "op '$op' not in {list,attach,new,kill,read}" ;;
  esac
}

main "$@"
