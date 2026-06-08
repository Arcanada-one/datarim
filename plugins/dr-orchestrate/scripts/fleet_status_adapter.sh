#!/usr/bin/env bash
# fleet_status_adapter.sh — Task status port: read/write fleet task status.
#
# Provides status_get and status_update functions that integrate with:
#   - Primary: fleet:task-events Redis Stream (XADD/XREVRANGE)
#   - Fallback/secondary: datarim/tasks.md (atomic write via temp+mv + flock)
#   - Future (stub): Munera billing API (DR_FLEET_MUNERA_ENABLE=1)
#
# Public functions:
#   status_get    <task_id>                    → prints status string
#   status_update <task_id> <status> [reason]  → publishes event + updates tasks.md
#
# Usage (standalone):
#   fleet_status_adapter.sh get    <task_id>
#   fleet_status_adapter.sh update <task_id> <status> [reason]
#   fleet_status_adapter.sh --help
#   fleet_status_adapter.sh --check
#
# Env:
#   DR_ORCH_REDIS_URL       Redis URL (default redis://127.0.0.1:6379)
#   DR_FLEET_BUS_BACKEND    "redis" or "mock" (default redis)
#   DR_FLEET_TASKS_FILE     Path to tasks.md (default: auto-detected from cwd)
#   DR_FLEET_MUNERA_ENABLE  Set to 1 to enable Munera stub (default 0)
#   DR_FLEET_LOCK_TIMEOUT   flock timeout in seconds (default 5)

set -uo pipefail

_self="${BASH_SOURCE[0]:-$0}"
PLUGIN_DIR="$(cd "$(dirname "$_self")/.." && pwd)"
BUS_ADAPTER="$PLUGIN_DIR/scripts/bus_adapter.sh"
AUDIT_SINK="$PLUGIN_DIR/scripts/audit_sink.sh"

: "${DR_ORCH_REDIS_URL:=redis://127.0.0.1:6379}"
: "${DR_FLEET_BUS_BACKEND:=redis}"
: "${DR_FLEET_MUNERA_ENABLE:=0}"
: "${DR_FLEET_LOCK_TIMEOUT:=5}"

# ── tasks.md location ─────────────────────────────────────────────────────────

_find_tasks_file() {
  # Explicit override takes priority
  if [[ -n "${DR_FLEET_TASKS_FILE:-}" ]]; then
    printf '%s' "$DR_FLEET_TASKS_FILE"
    return
  fi
  # Walk up from cwd looking for datarim/tasks.md
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/datarim/tasks.md" ]]; then
      printf '%s/datarim/tasks.md' "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
  printf ''
}

# ── status_get <task_id> ──────────────────────────────────────────────────────

# Returns the latest status for the task. Checks Redis XREVRANGE first,
# falls back to tasks.md grep.
status_get() {
  local task_id="$1"

  # Try Redis XREVRANGE for the latest lifecycle event for this task
  if [[ "$DR_FLEET_BUS_BACKEND" == "redis" ]] \
      && command -v redis-cli >/dev/null 2>&1; then
    local last_status
    last_status=$(redis-cli -u "$DR_ORCH_REDIS_URL" \
      XREVRANGE "stream:fleet:task-events" + - COUNT 100 2>/dev/null \
      | awk -v tid="$task_id" '
          /task_id/ { getline; if ($0 == tid) found=1 }
          found && /status/ { getline; print $0; exit }
        ' 2>/dev/null || true)
    if [[ -n "$last_status" ]]; then
      printf '%s\n' "$last_status"
      return 0
    fi
  fi

  # Fallback: grep tasks.md
  local tasks_file
  tasks_file="$(_find_tasks_file)"
  if [[ -n "$tasks_file" ]] && [[ -f "$tasks_file" ]]; then
    local status
    # tasks.md format: | ID | Title | L | Status | Since |
    status=$(grep -m1 "^| $task_id " "$tasks_file" 2>/dev/null \
      | awk -F'|' '{gsub(/ /,"",$5); print $5}' || true)
    if [[ -n "$status" ]]; then
      printf '%s\n' "$status"
      return 0
    fi
  fi

  printf 'unknown\n'
  return 0
}

# ── status_update <task_id> <status> [reason] ─────────────────────────────────

# 1. Publishes lifecycle event to fleet:task-events (primary truth)
# 2. Atomically updates tasks.md via temp+mv with advisory flock (secondary)
status_update() {
  local task_id="$1" new_status="$2" reason="${3:-}"

  # Source bus adapter for publishing and audit sink for redaction
  # shellcheck source=scripts/bus_adapter.sh
  source "$BUS_ADAPTER"
  # shellcheck source=scripts/audit_sink.sh
  source "$AUDIT_SINK"

  # Redact reason before it enters the fleet event stream (PRD § Security)
  local safe_reason
  safe_reason="$(redact_reason "$reason")"

  # Generate message ID
  local msg_id
  msg_id="status-$(date +%s%3N)-$$"

  # Publish to fleet:task-events (reason is redacted)
  bus_publish "fleet:task-events" \
    id          "$msg_id" \
    ts          "$(date -u +%FT%TZ)" \
    type        "lifecycle" \
    from        "pm-orchestrator" \
    to          "fleet-daemon" \
    task_id     "$task_id" \
    status      "$new_status" \
    reason      "$safe_reason" \
    >/dev/null

  # Munera stub (future integration point)
  if [[ "${DR_FLEET_MUNERA_ENABLE:-0}" == "1" ]]; then
    # TODO(operator): call Munera billing API to sync task status
    # DR_FLEET_MUNERA_HOST env required; stub returns success
    printf 'STUB: Munera status_update not yet provisioned\n' >&2
  fi

  # Update tasks.md atomically
  local tasks_file
  tasks_file="$(_find_tasks_file)"
  if [[ -z "$tasks_file" ]] || [[ ! -f "$tasks_file" ]]; then
    printf 'WARN: tasks.md not found — skipping file update\n' >&2
    return 0
  fi

  local tmp_file="${tasks_file}.tmp.$$"
  # Try flock if available; fall back to direct write
  if command -v flock >/dev/null 2>&1; then
    (
      flock -w "${DR_FLEET_LOCK_TIMEOUT}" 200 || {
        printf 'WARN: flock timeout (%ss) — proceeding without lock\n' \
          "$DR_FLEET_LOCK_TIMEOUT" >&2
      }
      # Rewrite tasks.md replacing the status column for the matching task ID
      awk -v tid="$task_id" -v ns="$new_status" -F'|' '
        /^\| / && $2 ~ "^[[:space:]]*"tid"[[:space:]]*$" {
          $5 = " " ns " "
          print $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6
          next
        }
        { print }
      ' OFS='|' "$tasks_file" > "$tmp_file" \
        && mv -f "$tmp_file" "$tasks_file"
    ) 200>"${tasks_file}.lock"
  else
    awk -v tid="$task_id" -v ns="$new_status" -F'|' '
      /^\| / && $2 ~ "^[[:space:]]*"tid"[[:space:]]*$" {
        $5 = " " ns " "
        print $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6
        next
      }
      { print }
    ' OFS='|' "$tasks_file" > "$tmp_file" \
      && mv -f "$tmp_file" "$tasks_file"
  fi

  return 0
}

# ── check / help ──────────────────────────────────────────────────────────────

_check() {
  local tasks_file
  tasks_file="$(_find_tasks_file)"
  printf 'backend=%s\nredis_url=%s\ntasks_file=%s\nmunera_enable=%s\n' \
    "$DR_FLEET_BUS_BACKEND" "$DR_ORCH_REDIS_URL" \
    "${tasks_file:-not-found}" "$DR_FLEET_MUNERA_ENABLE"
}

# ── CLI dispatch ──────────────────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    get)    shift; status_get "$@" ;;
    update) shift; status_update "$@" ;;
    --check) _check ;;
    --help)
      printf 'usage: fleet_status_adapter.sh get <task_id>\n'
      printf '       fleet_status_adapter.sh update <task_id> <status> [reason]\n'
      printf '       fleet_status_adapter.sh --check | --help\n'
      exit 0
      ;;
    *) printf 'ERR: unknown command %q\n' "${1:-}" >&2; exit 1 ;;
  esac
fi
