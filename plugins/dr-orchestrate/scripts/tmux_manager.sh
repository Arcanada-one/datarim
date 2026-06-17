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

# pane_send_content — deliver an arbitrary content payload (a brief, an article
# body, any non-command text that may contain non-ASCII and markup) to a pane.
#
# This is the content channel, distinct from pane_send (the command channel).
# The command-channel whitelist (`^[a-zA-Z0-9 _./:=@-]+$`) exists to keep
# orchestrator control commands ASCII-only; it deliberately does NOT apply here,
# because content legitimately carries cyrillic / markup / punctuation. The
# escape-injection guard (check_escape — the CVE-2019-9535 mitigation) and the
# cooldown / pane-blocked guards STILL apply: those are about safety, not
# alphabet. Delivery uses tmux load-buffer + paste-buffer rather than send-keys,
# so the payload is pasted as literal text and never interpreted as keystrokes.
#
# Args: <target-pane> <content-file>  (the brief is read from a file, never a
# shell arg, to avoid argv-length limits and quoting hazards on large bodies).
pane_send_content() {
  local target="$1"
  local content_file="$2"
  [[ -f "$content_file" ]] || { echo "ERR: content file not found: $content_file" >&2; return 1; }
  # Escape-injection guard stays (reads the payload from the file).
  bash "$DR_ORCH_DIR/scripts/security.sh" check_escape "$(cat "$content_file")" || return 1
  bash "$DR_ORCH_DIR/scripts/security.sh" check_cooldown "$target" micro || return 1
  if bash "$DR_ORCH_DIR/scripts/security.sh" is_pane_blocked "$target"; then
    echo "ERR: pane $target is blocked" >&2
    return 1
  fi
  # Load the file into a private tmux buffer, paste it into the pane, then submit.
  local buf="dr-content-$$-${RANDOM}"
  tmux load-buffer -b "$buf" "$content_file" || return 1
  tmux paste-buffer -d -b "$buf" -t "$target" || { tmux delete-buffer -b "$buf" 2>/dev/null; return 1; }
  tmux send-keys -t "$target" Enter
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

# --- Fleet interactive spawn (design 3a) --------------------------------------
# session_spawn_interactive launches a LIVE interactive CLI agent in a detached
# tmux session (operator correction A2 — NOT `claude --print` / headless). The
# orchestrator then drives it via pane_send (brief) + pane_capture_tail
# (targeted suffix) + pane_idle_check (hang detection).

session_spawn_interactive() {
  local session="$1" agent_cmd="$2" role="${3:-}"
  command -v tmux >/dev/null 2>&1 || { echo "ERR: tmux not installed" >&2; return 1; }
  [ -n "$session" ] && [ -n "$agent_cmd" ] || { echo "ERR: usage: session_spawn_interactive <session> <agent-cmd> [role]" >&2; return 2; }
  if tmux has-session -t "$session" 2>/dev/null; then
    return 0   # reuse existing session (PM decision)
  fi
  # remain-on-exit keeps the pane inspectable if the agent exits early.
  # A wide detached window keeps long session-start lines from wrapping (a
  # narrow default pane splits an injected allowlist mid-token on capture).
  tmux new-session -d -s "$session" -x "${DR_FLEET_PANE_COLS:-220}" -y "${DR_FLEET_PANE_ROWS:-50}" "$agent_cmd"
  tmux set-option -t "$session" remain-on-exit on 2>/dev/null || true
  # Per-role session-start injection (design 3b): when a role is given, scope the
  # live agent to its starter skill + allowed-tools, read from the role registry.
  # Plain `[ -n "$role" ] && ...` as the last statement would return 1 under
  # `set -e` when role is empty (the no-role path is valid) — use a full `if`.
  if [ -n "$role" ]; then
    _inject_role_context "$session" "$role"
  fi
}

# _inject_role_context <session> <role> — fetch the role's starter_skill +
# allowed_tools (subagent_resolver fleet_role_session_init) and deliver them to
# the live pane as ONE session-start message, through the same security pipeline
# as any other send (whitelist + escape-block + cooldown). A single send avoids
# the micro-cooldown that would block a second back-to-back send. Tools are
# space-joined because the send-keys whitelist forbids commas; the CSV form
# remains available to non-pane consumers via fleet_role_session_init directly.
_inject_role_context() {
  local session="$1" role="$2" raw skill tools
  raw="$(bash "$DR_ORCH_DIR/scripts/subagent_resolver.sh" fleet_role_session_init "$role" 2>/dev/null)" || {
    echo "ERR: cannot resolve role context: $role" >&2; return 1; }
  skill="$(printf '%s\n' "$raw" | grep '^STARTER_SKILL=' | head -1)"
  tools="$(printf '%s\n' "$raw" | grep '^ALLOWED_TOOLS=' | head -1 | tr ',' ' ')"
  if [ -n "$skill" ] || [ -n "$tools" ]; then
    pane_send "$session" "$skill $tools"
  fi
}

# pane_capture_tail <target> <n_lines> — targeted suffix of the pane buffer
# (NOT the full scrollback — anti-pattern transcript-passthrough). Reads the
# last n_lines non-blank visible lines.
#
# Capture into a variable first, then slice in-process: piping `tmux
# capture-pane` directly into `tail` lets `tail` close the pipe early, which
# raises SIGPIPE on tmux and — under `set -o pipefail` — yields an empty
# command substitution. Buffering the full output sidesteps that entirely.
pane_capture_tail() {
  local target="$1" n="${2:-10}" buf
  command -v tmux >/dev/null 2>&1 || return 1
  buf="$(tmux capture-pane -p -t "$target" 2>/dev/null)" || return 1
  printf '%s\n' "$buf" | awk 'NF' | tail -n "$n"
}

# pane_idle_check <target> <idle_secs> <deadline_secs> — buffer-diff hang
# detection. Polls the pane suffix; if it stops changing for idle_secs, report
# idle (rc 0). If it keeps changing up to deadline_secs, report not-idle (rc 1)
# — a slow-but-LIVE agent must not be killed (R-1). rc 2 = hung past deadline.
pane_idle_check() {
  local target="$1" idle_secs="$2" deadline="$3"
  command -v tmux >/dev/null 2>&1 || return 1
  local prev cur elapsed=0 unchanged=0
  # Buffer-then-slice (see pane_capture_tail) to survive SIGPIPE under pipefail.
  prev="$(pane_capture_tail "$target" 5)"
  while [ "$elapsed" -lt "$deadline" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
    cur="$(pane_capture_tail "$target" 5)"
    if [ "$cur" = "$prev" ]; then
      unchanged=$((unchanged + 1))
      if [ "$unchanged" -ge "$idle_secs" ]; then
        return 0   # idle (agent done or genuinely stuck-but-quiet)
      fi
    else
      unchanged=0   # output changed → still live
      return 1      # not idle within the observation window (R-1: do not kill)
    fi
    prev="$cur"
  done
  return 2   # never went idle and never produced fresh output → hung past deadline
}

# session_close <session> — terminate a fleet session (PM decision after result
# extraction). Reuse is the alternative (session_spawn_interactive is idempotent).
session_close() {
  local session="$1"
  command -v tmux >/dev/null 2>&1 || return 1
  tmux kill-session -t "$session" 2>/dev/null || true
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
