#!/usr/bin/env bash
# tmux_manager.sh — session/pane CRUD for dr-orchestrate plugin (Phase 1, TUNE-0164)
# V-AC: 2 (session_init), 3 (pane_split), 4 (pane_kill), 5 (pane_send via security pipeline)
set -euo pipefail

if [[ -z "${DR_ORCH_DIR:-}" ]]; then
  DR_ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  export DR_ORCH_DIR
fi

session_init() {
  local s="${1:-datarim}"
  if tmux has-session -t "$s" 2>/dev/null; then
    return 0
  fi
  tmux new-session -d -s "$s"
}

pane_split() {
  local s="$1"
  tmux split-window -t "$s"
}

pane_kill() {
  local target="$1"
  tmux kill-pane -t "$target"
}

pane_capture() {
  local target="$1"
  # Test seam: when DR_ORCH_PANE_CAPTURE_OVERRIDE is set, emit its value instead
  # of invoking tmux. Default-off — zero impact on production when unset.
  if [[ -n "${DR_ORCH_PANE_CAPTURE_OVERRIDE:-}" ]]; then
    printf '%s\n' "$DR_ORCH_PANE_CAPTURE_OVERRIDE"
    return 0
  fi
  tmux capture-pane -p -t "$target"
}

pane_send() {
  local target="$1"
  local text="$2"
  bash "$DR_ORCH_DIR/scripts/security.sh" check_whitelist "$text" || return 1
  bash "$DR_ORCH_DIR/scripts/security.sh" check_escape    "$text" || return 1
  bash "$DR_ORCH_DIR/scripts/security.sh" check_cooldown  "$target" micro || return 1
  if bash "$DR_ORCH_DIR/scripts/security.sh" is_pane_blocked "$target"; then
    echo "ERR: pane $target is blocked" >&2
    return 1
  fi
  tmux send-keys -t "$target" -- "$text" Enter
}

# TUNE-0295 Phase B: list/attach/new + *_safe wrappers for tmux_dispatcher.

list() {
  tmux list-panes -a -F '#{pane_id}|#{session_name}|#{pane_current_command}|#{pane_pid}' 2>/dev/null || return 1
}

attach() {
  local pane="$1" task_id="$2"
  printf 'tmux attach-session -t %s \\; select-pane -t %s\n' "datarim" "$pane"
  : "$task_id"
}

new() {
  local task_id="$1" cmd="$2"
  tmux new-session -d -s "$task_id" "$cmd"
}

tmux_list_panes_safe() {
  command -v tmux >/dev/null 2>&1 || return 1
  list
}

tmux_new_session_safe() {
  command -v tmux >/dev/null 2>&1 || return 1
  new "$1" "$2"
}

tmux_kill_pane_safe() {
  command -v tmux >/dev/null 2>&1 || return 1
  tmux kill-pane -t "$1" 2>/dev/null
}

tmux_capture_pane_safe() {
  command -v tmux >/dev/null 2>&1 || return 1
  tmux capture-pane -p -t "$1" 2>/dev/null
}

# V-AC adjacency: floor = tmux 1.7 (capture-pane). Plan §5.3 / fixtures F3.
tmux_version_check() {
  local v
  v="$(tmux -V 2>/dev/null | awk '{print $2}')"
  [[ -n "$v" ]] || { echo "ERR: tmux not installed or unreachable" >&2; return 1; }
  awk -v v="$v" 'BEGIN { if (v+0 >= 1.7) exit 0; exit 1 }' \
    || { echo "ERR: tmux >=1.7 required (have $v)" >&2; return 1; }
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fn="${1:-}"; shift || true
  [[ -n "$fn" ]] || { echo "usage: tmux_manager.sh <fn> [args]" >&2; exit 2; }
  "$fn" "$@"
fi
