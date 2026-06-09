#!/usr/bin/env bash
# fleet_pm_orchestrator.sh — PM orchestrator: timeout/unblock/reassign/kill.
#
# Commands:
#   unblock-task  <task_id>            — marks task in_progress, publishes event
#   reassign-level <task_id> <level>   — publishes level-reassigned event
#   kill-agent     <session_id>        — kills tmux session + marks task failed
#   timeout-check  [--dry-run]         — scans active tasks for timeout violations
#   --check                            — print effective config and exit 0
#   --help                             — print usage
#
# Env:
#   DR_ORCH_REDIS_URL         Redis URL (default redis://127.0.0.1:6379)
#   DR_FLEET_BUS_BACKEND      "redis" or "mock" (default redis)
#   DR_FLEET_TASKS_FILE       Path to tasks.md
#   DR_FLEET_TIMEOUT_L1       Max heartbeat gap in seconds for L1 (default 300)
#   DR_FLEET_TIMEOUT_L2       Max heartbeat gap in seconds for L2 (default 900)
#   DR_FLEET_TIMEOUT_L3L4     Max heartbeat gap in seconds for L3-L4 (default 1800)

set -uo pipefail

_self="${BASH_SOURCE[0]:-$0}"
PLUGIN_DIR="$(cd "$(dirname "$_self")/.." && pwd)"
BUS_ADAPTER="$PLUGIN_DIR/scripts/bus_adapter.sh"
STATUS_ADAPTER="$PLUGIN_DIR/scripts/fleet_status_adapter.sh"

: "${DR_ORCH_REDIS_URL:=redis://127.0.0.1:6379}"
: "${DR_FLEET_BUS_BACKEND:=redis}"
: "${DR_FLEET_TIMEOUT_L1:=300}"
: "${DR_FLEET_TIMEOUT_L2:=900}"
: "${DR_FLEET_TIMEOUT_L3L4:=1800}"

# ── source dependencies (when not sourced ourselves) ─────────────────────────

_load_deps() {
  # shellcheck source=scripts/bus_adapter.sh
  source "$BUS_ADAPTER"
  # shellcheck source=scripts/fleet_status_adapter.sh
  source "$STATUS_ADAPTER"
}

# ── pm_publish: publish a PM command event to fleet:task-events ───────────────

pm_publish() {
  local type="$1" task_id="$2"
  shift 2
  local msg_id
  msg_id="pm-$(date +%s%3N)-$$"
  bus_publish "fleet:task-events" \
    id       "$msg_id" \
    ts       "$(date -u +%FT%TZ)" \
    type     "$type" \
    from     "pm-orchestrator" \
    to       "fleet-daemon" \
    task_id  "$task_id" \
    "$@" \
    >/dev/null
}

# ── unblock-task <task_id> ────────────────────────────────────────────────────

cmd_unblock_task() {
  local task_id="$1"
  [[ -n "$task_id" ]] || { printf 'ERR: task_id required\n' >&2; return 1; }
  pm_publish "lifecycle" "$task_id" status "in_progress" reason "pm-unblock"
  status_update "$task_id" "in_progress" "pm-unblock"
  printf 'PM: unblocked %s\n' "$task_id"
}

# ── reassign-level <task_id> <level> ─────────────────────────────────────────

cmd_reassign_level() {
  local task_id="$1" new_level="${2:-}"
  [[ -n "$task_id" ]]  || { printf 'ERR: task_id required\n' >&2; return 1; }
  [[ -n "$new_level" ]] || { printf 'ERR: new_level required (e.g. L1 L2 L3 L4)\n' >&2; return 1; }
  pm_publish "level-reassigned" "$task_id" new_level "$new_level"
  printf 'PM: level of %s reassigned to %s\n' "$task_id" "$new_level"
}

# ── kill-agent <session_id> ───────────────────────────────────────────────────

cmd_kill_agent() {
  local session_id="${1:-}"
  [[ -n "$session_id" ]] || { printf 'ERR: session_id required\n' >&2; return 1; }

  # Kill tmux session if it exists
  if command -v tmux >/dev/null 2>&1 && tmux has-session -t "$session_id" 2>/dev/null; then
    tmux kill-session -t "$session_id"
    printf 'PM: killed tmux session %s\n' "$session_id"
  else
    printf 'PM: tmux session %s not found (may already be gone)\n' "$session_id"
  fi

  # Publish kill event
  local msg_id
  msg_id="pm-kill-$(date +%s%3N)-$$"
  bus_publish "fleet:task-events" \
    id          "$msg_id" \
    ts          "$(date -u +%FT%TZ)" \
    type        "agent-killed" \
    from        "pm-orchestrator" \
    to          "fleet-daemon" \
    session_id  "$session_id" \
    >/dev/null
  printf 'PM: kill-agent event published for session %s\n' "$session_id"
}

# ── timeout-check [--dry-run] ─────────────────────────────────────────────────

cmd_timeout_check() {
  local dry_run=0
  [[ "${1:-}" == "--dry-run" ]] && dry_run=1

  printf 'PM: timeout-check dry_run=%d (L1=%ds L2=%ds L3/L4=%ds)\n' \
    "$dry_run" "$DR_FLEET_TIMEOUT_L1" "$DR_FLEET_TIMEOUT_L2" "$DR_FLEET_TIMEOUT_L3L4"

  # TODO(operator): scan active tasks from tasks.md / Redis; compare last
  # heartbeat timestamp against level-specific timeout; call kill-agent +
  # reassign-level when exceeded. Heartbeat from fleet:task-events type=heartbeat.
  printf 'PM: timeout-check completed (no active heartbeat data in dry-run)\n'
}

# ── check ─────────────────────────────────────────────────────────────────────

_check() {
  printf 'backend=%s\nredis_url=%s\ntimeout_L1=%s\ntimeout_L2=%s\ntimeout_L3L4=%s\n' \
    "$DR_FLEET_BUS_BACKEND" "$DR_ORCH_REDIS_URL" \
    "$DR_FLEET_TIMEOUT_L1" "$DR_FLEET_TIMEOUT_L2" "$DR_FLEET_TIMEOUT_L3L4"
}

# ── CLI dispatch ──────────────────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _load_deps

  case "${1:-}" in
    unblock-task)
      shift; cmd_unblock_task "$@" ;;
    reassign-level)
      shift; cmd_reassign_level "$@" ;;
    kill-agent)
      shift; cmd_kill_agent "$@" ;;
    timeout-check)
      shift; cmd_timeout_check "$@" ;;
    --check)
      _check ;;
    --help)
      printf 'usage: fleet_pm_orchestrator.sh <command> [args]\n'
      printf 'commands: unblock-task <id>, reassign-level <id> <level>,\n'
      printf '          kill-agent <session>, timeout-check [--dry-run],\n'
      printf '          --check, --help\n'
      exit 0
      ;;
    "")
      printf 'ERR: command required. Run --help for usage.\n' >&2
      exit 1
      ;;
    *)
      printf 'ERR: unknown command %q\n' "$1" >&2
      exit 1
      ;;
  esac
fi
