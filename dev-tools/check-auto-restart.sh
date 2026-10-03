#!/usr/bin/env bash
# Verify single-host tmux recovery and idempotent interrupted-cycle marking.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../plugins/dr-orchestrate/tests/helpers/phase3-env.bash
source "$ROOT/plugins/dr-orchestrate/tests/helpers/phase3-env.bash"

usage() {
  echo "usage: check-auto-restart.sh --session <name> --expect-restore" >&2
  exit 2
}

SESSION=""; EXPECT_RESTORE=0
while (( $# > 0 )); do
  case "$1" in
    --session) SESSION="${2:-}"; shift 2 ;;
    --expect-restore) EXPECT_RESTORE=1; shift ;;
    *) usage ;;
  esac
done
[[ "$SESSION" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]] || usage
(( EXPECT_RESTORE == 1 )) || usage

phase3_env_setup
trap phase3_env_cleanup EXIT
MANAGER="$PHASE3_PLUGIN_ROOT/scripts/tmux_manager.sh"
AUDIT_SINK="$PHASE3_PLUGIN_ROOT/scripts/audit_sink.sh"
[[ -x "$MANAGER" && -x "$AUDIT_SINK" ]] || {
  echo "FAIL: recovery dependencies are not executable" >&2
  exit 1
}

# shellcheck source=../plugins/dr-orchestrate/scripts/tmux_manager.sh
source "$MANAGER"
# shellcheck source=../plugins/dr-orchestrate/scripts/audit_sink.sh
source "$AUDIT_SINK"

UNRELATED="phase3-unrelated-$$"
tmux new-session -d -s "$UNRELATED"
unrelated_pane="$(tmux display-message -p -t "$UNRELATED:0.0" '#{pane_id}')"

tmux kill-session -t "$SESSION" >/dev/null 2>&1 || true
session_recover "$SESSION"
tmux has-session -t "$SESSION"

tmux set-option -t "$SESSION" remain-on-exit on
respawn_once="$PHASE3_ENV_ROOT/respawn-once.sh"
respawn_marker="$PHASE3_ENV_ROOT/respawn.marker"
cat >"$respawn_once" <<'SH'
#!/usr/bin/env bash
if [[ ! -e "${PHASE3_RESPAWN_MARKER:?}" ]]; then
  : >"$PHASE3_RESPAWN_MARKER"
  exit 0
fi
exec sleep 600
SH
chmod 700 "$respawn_once"
tmux set-environment -g PHASE3_RESPAWN_MARKER "$respawn_marker"
tmux respawn-pane -k -t "$SESSION:0.0" "$respawn_once"
dead=0
for _ in $(seq 1 100); do
  [[ "$(tmux display-message -p -t "$SESSION:0.0" '#{pane_dead}')" == 1 ]] && { dead=1; break; }
done
(( dead == 1 )) || { echo "FAIL: fixture pane did not become inactive" >&2; exit 1; }
session_recover "$SESSION"
[[ "$(tmux display-message -p -t "$SESSION:0.0" '#{pane_dead}')" == 0 ]] || {
  echo "FAIL: inactive retained pane was not respawned" >&2
  exit 1
}

CYCLE_ID="phase3-cycle-$$"
PANE_ID="$SESSION:0.0"
emit "$DR_ORCH_AUDIT_FILE" \
  "$(make_cycle_checkpoint prepare "$CYCLE_ID" "$SESSION" "$PANE_ID" /dr-plan pending)"
recover_cycle_checkpoint "$DR_ORCH_AUDIT_FILE" "$SESSION" "$PANE_ID"
recover_cycle_checkpoint "$DR_ORCH_AUDIT_FILE" "$SESSION" "$PANE_ID"
recovery_count="$(jq -s --arg cycle "$CYCLE_ID" \
  '[.[] | select(.event=="cycle_checkpoint" and .phase=="recovery" and .cycle_id==$cycle)] | length' \
  "$DR_ORCH_AUDIT_FILE")"
[[ "$recovery_count" == 1 ]] || { echo "FAIL: checkpoint recovery was not idempotent" >&2; exit 1; }
[[ ! -s "$DR_ORCH_ACTION_EXECUTOR_LOG" ]] || { echo "FAIL: recovery replayed an action" >&2; exit 1; }
[[ "$(tmux display-message -p -t "$UNRELATED:0.0" '#{pane_id}')" == "$unrelated_pane" ]] || {
  echo "FAIL: unrelated tmux session changed" >&2
  exit 1
}

echo "PASS: session=$SESSION recreated=true pane_respawned=true recovery_events=1 action_replays=0"
