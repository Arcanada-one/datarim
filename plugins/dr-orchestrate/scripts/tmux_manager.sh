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

# Restore a missing session or a dead primary pane without replaying commands.
session_recover() {
  local s="${1:-datarim}"
  if ! tmux has-session -t "$s" 2>/dev/null; then
    session_init "$s"
    return 0
  fi
  if [[ "$(tmux display-message -p -t "$s:0.0" '#{pane_dead}' 2>/dev/null || echo 1)" == "1" ]]; then
    tmux respawn-pane -k -t "$s:0.0"
  fi
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
  # A small settle delay between the paste and the Enter is required: an
  # interactive TUI ingests a paste asynchronously (echo, re-wrap, fold large
  # pastes into a placeholder), and an Enter sent back-to-back races that ingest
  # and is dropped — leaving the prompt unsubmitted in the input box. The delay
  # lets the paste land before the submit keystroke.
  local buf="dr-content-$$-${RANDOM}"
  tmux load-buffer -b "$buf" "$content_file" || return 1
  tmux paste-buffer -d -b "$buf" -t "$target" || { tmux delete-buffer -b "$buf" 2>/dev/null; return 1; }
  sleep "${DR_PANE_SUBMIT_DELAY:-2}"
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
  local session="$1" agent_cmd="$2" role="${3:-}" pane_dead
  command -v tmux >/dev/null 2>&1 || { echo "ERR: tmux not installed" >&2; return 1; }
  [ -n "$session" ] && [ -n "$agent_cmd" ] || { echo "ERR: usage: session_spawn_interactive <session> <agent-cmd> [role]" >&2; return 2; }
  if tmux has-session -t "$session" 2>/dev/null; then
    pane_dead="$(tmux display-message -p -t "$session" '#{pane_dead}' 2>/dev/null || printf 1)"
    if [ "$pane_dead" != 1 ]; then
      # Reuse keeps the process, not the prior role. Re-project the requested
      # role so a developer -> designer handoff cannot retain stale authority.
      if [ -n "$role" ]; then
        # The initial role projection may have just used the pane's 500 ms
        # security cooldown. Honour that boundary instead of bypassing it.
        sleep 0.6
        _inject_role_context "$session" "$role"
      fi
      return 0
    fi
    if bash "$DR_ORCH_DIR/scripts/context_window_setup.sh" enabled >/dev/null 2>&1; then
      _session_spawn_with_context "$session" "$agent_cmd" "$role"
      return
    fi
    tmux respawn-pane -k -t "$session" "$agent_cmd"
    # respawn-pane creates a new agent process; it needs the same role-start
    # projection as a newly created session.
    if [ -n "$role" ]; then
      sleep 0.6
      _inject_role_context "$session" "$role"
    fi
    return
  fi
  if bash "$DR_ORCH_DIR/scripts/context_window_setup.sh" enabled >/dev/null 2>&1; then
    _session_spawn_with_context "$session" "$agent_cmd" "$role"
    return
  fi
  # remain-on-exit keeps the pane inspectable if the agent exits early.
  # A wide detached window keeps long session-start lines from wrapping (a
  # narrow default pane splits an injected allowlist mid-token on capture).
  tmux new-session -d -s "$session" -x "${DR_FLEET_PANE_COLS:-420}" -y "${DR_FLEET_PANE_ROWS:-50}" "$agent_cmd"
  tmux set-option -t "$session" remain-on-exit on 2>/dev/null || true
  # Per-role session-start injection (design 3b): when a role is given, scope the
  # live agent to its starter skill + allowed-tools, read from the role registry.
  # Plain `[ -n "$role" ] && ...` as the last statement would return 1 under
  # `set -e` when role is empty (the no-role path is valid) — use a full `if`.
  if [ -n "$role" ]; then
    _inject_role_context "$session" "$role"
  fi
}

_session_spawn_with_context() {
  local session="$1" agent_cmd="$2" role="$3" runtime task workspace pane epoch socket setup_out instance incarnation overlay birth launch meta barrier
  runtime="${DR_ORCH_RUNTIME:-}"; task="${DR_ORCH_ACTIVE_TASK:-}"; workspace="${DR_ORCH_WORKSPACE:-$PWD}"
  case "$runtime" in claude|codex) ;; *) echo 'ERR: DR_ORCH_RUNTIME must be claude or codex' >&2; return 2 ;; esac
  [[ "$task" =~ ^[A-Z]+-[0-9]+$ ]] || { echo 'ERR: DR_ORCH_ACTIVE_TASK is required' >&2; return 2; }
  if ! tmux has-session -t "$session" 2>/dev/null; then
    tmux new-session -d -s "$session" -x "${DR_FLEET_PANE_COLS:-420}" -y "${DR_FLEET_PANE_ROWS:-50}" 'sleep 30'
  fi
  tmux set-option -t "$session" remain-on-exit on 2>/dev/null || true
  pane="$(tmux display-message -p -t "$session" '#{pane_id}')"
  socket="$(tmux display-message -p -t "$session" '#{socket_path}')"
  epoch="$(tmux show-options -gv @datarim_context_epoch 2>/dev/null || true)"
  if [ -z "$epoch" ]; then epoch="$(openssl rand -hex 16)"; tmux set-option -g @datarim_context_epoch "$epoch"; fi
  setup_out="$(DR_ORCH_CONTEXT_PANE="$pane" DR_ORCH_CONTEXT_EPOCH="$epoch" DR_ORCH_CONTEXT_SOCKET="$socket" DR_ORCH_ACTIVE_TASK="$task" \
    bash "$DR_ORCH_DIR/scripts/context_window_setup.sh" install --runtime "$runtime")" || { tmux kill-session -t "$session"; return 1; }
  instance="$(printf '%s\n' "$setup_out" | awk -F= '$1=="instance"{print $2; exit}')"
  incarnation="$(printf '%s\n' "$setup_out" | awk -F= '$1=="incarnation"{print $2; exit}')"
  overlay="$(printf '%s\n' "$setup_out" | awk -F= '$1=="overlay"{sub(/^overlay=/, ""); print; exit}')"
  [ -n "$instance" ] && [ -n "$incarnation" ] && [ -n "$overlay" ] || { tmux kill-session -t "$session"; return 1; }
  if [ "$runtime" = claude ]; then launch="$agent_cmd --settings $(printf '%q' "$overlay")"; else launch="$agent_cmd --profile datarim-orchestrate-context"; fi
  launch="env DR_ORCH_DIR=$(printf '%q' "$DR_ORCH_DIR") DR_ORCH_CONTEXT_STATE=$(printf '%q' "${DR_ORCH_CONTEXT_STATE:-${DR_ORCH_STATE_DIR:-$HOME/.local/share/datarim-orchestrate/state}/context-window}") DR_ORCH_CONTEXT_TRUST_ROOT=$(printf '%q' "${DR_ORCH_CONTEXT_TRUST_ROOT:-$HOME}") DR_ORCH_USER_CONFIG=$(printf '%q' "${DR_ORCH_USER_CONFIG:-$DR_ORCH_DIR/user-config.yaml}") HOME=$(printf '%q' "$HOME") CODEX_HOME=$(printf '%q' "${CODEX_HOME:-$HOME/.codex}") DR_ORCH_CONTEXT_INSTANCE=$(printf '%q' "$instance") DR_ORCH_CONTEXT_INCARNATION=$(printf '%q' "$incarnation") DR_ORCH_CONTEXT_PANE=$(printf '%q' "$pane") DR_ORCH_ACTIVE_TASK=$(printf '%q' "$task") DR_ORCH_WORKSPACE=$(printf '%q' "$workspace") $launch"
  meta="${DR_ORCH_CONTEXT_STATE:-${DR_ORCH_STATE_DIR:-$HOME/.local/share/datarim-orchestrate/state}/context-window}/instances/$instance.meta.json"
  barrier="while grep -q '\"runtime_bound\":false' $(printf '%q' "$meta"); do sleep 0.01; done; exec $launch"
  tmux respawn-pane -k -t "$session" "$barrier"
  birth="$(tmux display-message -p -t "$session" '#{pane_pid}')"
  bash "$DR_ORCH_DIR/scripts/context_window_setup.sh" bind-process "$instance" "$incarnation" "$birth"
  if [ -n "$role" ]; then _inject_role_context "$session" "$role"; fi
}

# _inject_role_context <session> <role> — fetch the complete role projection
# (identity, skills, tools, paths, product-code access, and forbidden actions)
# and deliver it to the live pane as ONE session-start message through the same
# security pipeline as any other send. A single send avoids the micro-cooldown
# that would block a second back-to-back send. Commas/newlines are space-joined
# because the send-keys whitelist forbids them; the machine-readable line form
# remains available via fleet_role_session_init directly.
_inject_role_context() {
  local session="$1" role="$2" raw message
  raw="$(bash "$DR_ORCH_DIR/scripts/subagent_resolver.sh" fleet_role_session_init "$role" 2>/dev/null)" || {
    echo "ERR: cannot resolve role context: $role" >&2; return 1; }
  message="$(printf '%s\n' "$raw" | tr '\n,' '  ' | sed 's/[[:space:]][[:space:]]*/ /g; s/[[:space:]]$//')"
  [ -n "$message" ] || { echo "ERR: empty role context: $role" >&2; return 1; }
  pane_send "$session" "$message"
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
  local session="$1" pane="" killed=0 state_root map
  command -v tmux >/dev/null 2>&1 || return 1
  pane="$(tmux display-message -p -t "$session" '#{pane_id}' 2>/dev/null || true)"
  if tmux kill-session -t "$session" 2>/dev/null; then killed=1; fi
  state_root="${DR_ORCH_CONTEXT_STATE:-${DR_ORCH_STATE_DIR:-$HOME/.local/share/datarim-orchestrate/state}/context-window}"
  map="$state_root/active/$(printf '%s' "$pane" | tr -c 'A-Za-z0-9_.-' '_').map"
  if [ "$killed" -eq 1 ] && [ -n "$pane" ] && [ -f "$map" ] && ! tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -Fxq "$pane"; then
    bash "$DR_ORCH_DIR/scripts/context_window_setup.sh" retire --pane "$pane" 2>/dev/null || return 1
  fi
  [ "$killed" -eq 1 ]
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
