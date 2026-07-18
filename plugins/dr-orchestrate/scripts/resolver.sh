#!/usr/bin/env bash
# resolver.sh — bounded, trusted resolver-history compatibility CLI.
set -euo pipefail

umask 077

DR_ORCH_DIR="${DR_ORCH_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DR_ORCH_STATE_DIR="${DR_ORCH_STATE_DIR:-${STATE_DIR:-$HOME/.local/share/dr-orchestrate/state}}"
DR_ORCH_RULES_DEFAULT="${DR_ORCH_RULES_DEFAULT:-$DR_ORCH_DIR/rules/default.yaml}"
DR_ORCH_RULES_USER="${DR_ORCH_RULES_USER:-$HOME/.config/dr-orchestrate/rules/user.yaml}"
DR_ORCH_AUDIT_FILE="${DR_ORCH_AUDIT_FILE:-$DR_ORCH_STATE_DIR/resolver-audit.jsonl}"
DR_ORCH_LOCK_TIMEOUT="${DR_ORCH_LOCK_TIMEOUT:-5}"

readonly HISTORY_FILE="$DR_ORCH_STATE_DIR/resolver-history.jsonl"
readonly LOCK_FILE="$DR_ORCH_STATE_DIR/.resolver-history.lock"
readonly RESOLVER_HISTORY_LIB="$DR_ORCH_DIR/scripts/lib/resolver_history.py"
readonly HISTORY_MAX_RECORDS=5000
readonly HISTORY_MAX_BYTES=1048576

_error() {
  printf 'resolver: %s\n' "$*" >&2
}

_usage() {
  printf '%s\n' \
    'usage: resolver.sh record <intent> <action> <exit-code>' \
    '       resolver.sh suggest_alternative <intent>'
}

_require_dependencies() {
  local dependency
  for dependency in flock jq python3 yq; do
    command -v "$dependency" >/dev/null 2>&1 || {
      _error "required dependency unavailable: $dependency"
      return 2
    }
  done
  [[ -f "$RESOLVER_HISTORY_LIB" ]] || {
    _error "resolver-history library unavailable: $RESOLVER_HISTORY_LIB"
    return 2
  }
}

_validate_state_path() {
  [[ -n "$DR_ORCH_STATE_DIR" && "$DR_ORCH_STATE_DIR" != "/" ]] || {
    _error 'DR_ORCH_STATE_DIR must name a dedicated directory'
    return 2
  }
  [[ ! -L "$DR_ORCH_STATE_DIR" ]] || {
    _error 'state directory must not be a symlink'
    return 2
  }
  if [[ -e "$DR_ORCH_STATE_DIR" && ! -d "$DR_ORCH_STATE_DIR" ]]; then
    _error 'state path is not a directory'
    return 2
  fi

  mkdir -p -- "$DR_ORCH_STATE_DIR"
  chmod 700 -- "$DR_ORCH_STATE_DIR"
}

_validate_regular_or_absent() {
  local path="$1"
  [[ ! -L "$path" ]] || {
    _error "refusing symlink path: $path"
    return 2
  }
  if [[ -e "$path" && ! -f "$path" ]]; then
    _error "path is not a regular file: $path"
    return 2
  fi
}

_normalize_intent() {
  python3 "$RESOLVER_HISTORY_LIB" normalize "$1"
}

_registry_source_json() {
  local source="$1"
  if [[ ! -f "$source" || ! -s "$source" ]]; then
    printf '[]\n'
    return 0
  fi
  yq eval -o=json '.patterns // []' -- "$source" 2>/dev/null || printf '[]\n'
}

_trusted_registry_json() {
  local bundled user
  bundled="$(_registry_source_json "$DR_ORCH_RULES_DEFAULT")"
  user="$(_registry_source_json "$DR_ORCH_RULES_USER")"
  jq -cn --argjson bundled "$bundled" --argjson user "$user" '
    [$bundled, $user]
    | map(if type == "array" then . else [] end)
    | add
    | [ .[]?
        | .action?
        | strings
        | select(test("^/dr-[a-z0-9][a-z0-9-]*$")) ]
    | unique
    | sort
  '
}

_canonical_action() {
  local registry="$2" candidate="$1"
  if [[ "$candidate" =~ ^dr-[a-z0-9][a-z0-9-]*$ ]]; then
    candidate="/$candidate"
  fi
  [[ "$candidate" =~ ^/dr-[a-z0-9][a-z0-9-]*$ ]] || return 2
  jq -e --arg action "$candidate" 'index($action) != null' <<<"$registry" >/dev/null \
    || return 2
  printf '%s\n' "$candidate"
}

_now_epoch() {
  local now="${DR_ORCH_NOW_EPOCH:-}"
  if [[ -z "$now" ]]; then
    now="$(date +%s)"
  fi
  [[ "$now" =~ ^[0-9]+$ ]] || return 2
  printf '%s\n' "$now"
}

_emit_corrupt_audit_locked() {
  local corrupt_count="$1" now audit_parent payload
  [[ "$corrupt_count" =~ ^[1-9][0-9]*$ ]] || return 0
  now="$(_now_epoch)" || return 2
  audit_parent="$(dirname "$DR_ORCH_AUDIT_FILE")"
  [[ ! -L "$audit_parent" ]] || return 2
  mkdir -p -- "$audit_parent"
  _validate_regular_or_absent "$DR_ORCH_AUDIT_FILE" || return 2
  payload="$(jq -nc \
    --arg event_type resolver_history_corrupt \
    --argjson timestamp "$now" \
    --argjson corrupt_count "$corrupt_count" \
    '{event_type:$event_type,timestamp:$timestamp,corrupt_count:$corrupt_count}')"
  printf '%s\n' "$payload" >> "$DR_ORCH_AUDIT_FILE"
  chmod 600 -- "$DR_ORCH_AUDIT_FILE"
}

# Rebuild a canonical suffix under the already-held lock. Passing a JSON record
# appends it before count/byte rotation; an empty argument performs maintenance.
_rotate_history_locked() {
  local new_record="${1:-}" temporary corrupt_count
  _validate_regular_or_absent "$HISTORY_FILE" || return 2
  temporary="$(mktemp "$DR_ORCH_STATE_DIR/.resolver-history.XXXXXX")"
  chmod 600 -- "$temporary"

  if ! corrupt_count="$(python3 "$RESOLVER_HISTORY_LIB" rotate \
      "$HISTORY_FILE" "$temporary" "$HISTORY_MAX_RECORDS" "$HISTORY_MAX_BYTES" \
      "$new_record")"; then
    rm -f -- "$temporary"
    return 2
  fi

  mv -f -- "$temporary" "$HISTORY_FILE"
  chmod 600 -- "$HISTORY_FILE"
  _emit_corrupt_audit_locked "$corrupt_count"
}

_record_locked() {
  local intent="$1" action="$2" exit_code="$3" timestamp="$4" record
  record="$(jq -nc \
    --arg intent "$intent" \
    --arg action "$action" \
    --argjson exit_code "$exit_code" \
    --argjson timestamp "$timestamp" \
    '{intent:$intent,action:$action,exit_code:$exit_code,timestamp:$timestamp}')"
  _rotate_history_locked "$record"
}

_suggest_locked() {
  local intent="$1" registry="$2"
  _validate_regular_or_absent "$HISTORY_FILE" || return 2
  [[ -f "$HISTORY_FILE" ]] || return 0
  _rotate_history_locked
  [[ -s "$HISTORY_FILE" ]] || return 0

  python3 "$RESOLVER_HISTORY_LIB" suggest "$HISTORY_FILE" "$intent" "$registry"
}

_with_lock() (
  local operation="$1"
  shift
  _validate_state_path || exit $?
  _validate_regular_or_absent "$LOCK_FILE" || exit $?
  : >> "$LOCK_FILE"
  chmod 600 -- "$LOCK_FILE"
  exec 9>> "$LOCK_FILE"
  flock -w "$DR_ORCH_LOCK_TIMEOUT" 9 || {
    _error 'timed out acquiring resolver-history lock'
    exit 2
  }
  "$operation" "$@"
)

record() {
  [[ $# -eq 3 ]] || { _usage >&2; return 2; }
  local normalized registry canonical exit_code="$3" timestamp
  if ! normalized="$(_normalize_intent "$1")"; then
    _error 'invalid intent'
    return 2
  fi
  [[ "$exit_code" =~ ^[0-9]+$ && "$exit_code" -le 255 ]] || {
    _error 'exit code must be an integer from 0 through 255'
    return 2
  }
  registry="$(_trusted_registry_json)"
  if ! canonical="$(_canonical_action "$2" "$registry")"; then
    _error 'action is not present in the trusted default/user registry'
    return 2
  fi
  timestamp="$(_now_epoch)" || {
    _error 'invalid DR_ORCH_NOW_EPOCH'
    return 2
  }
  _with_lock _record_locked "$normalized" "$canonical" "$exit_code" "$timestamp"
}

suggest_alternative() {
  [[ $# -eq 1 ]] || { _usage >&2; return 2; }
  local normalized registry
  if ! normalized="$(_normalize_intent "$1")"; then
    _error 'invalid intent'
    return 2
  fi
  registry="$(_trusted_registry_json)"
  _with_lock _suggest_locked "$normalized" "$registry"
}

main() {
  _require_dependencies || return $?
  [[ "$DR_ORCH_LOCK_TIMEOUT" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
    _error 'DR_ORCH_LOCK_TIMEOUT must be a non-negative number'
    return 2
  }
  local command="${1:-}"
  [[ -n "$command" ]] || { _usage >&2; return 2; }
  shift
  case "$command" in
    record) record "$@" ;;
    suggest_alternative) suggest_alternative "$@" ;;
    -h|--help) _usage ;;
    *) _error "unknown command: $command"; _usage >&2; return 2 ;;
  esac
}

main "$@"
