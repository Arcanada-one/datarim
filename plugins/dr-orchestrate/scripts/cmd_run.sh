#!/usr/bin/env bash
# cmd_run.sh — entry point for `dr-orchestrate run`.
# Phase 1 (TUNE-0164): single iteration, lean rule-based.
set -euo pipefail

[[ "${BASH_VERSINFO[0]}" -ge 4 ]] || { echo "ERR: bash 4+ required (have $BASH_VERSION)" >&2; exit 1; }

DR_ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DR_ORCH_DIR

# Stateful modules must see one canonical root. Keep STATE_DIR as the legacy
# compatibility alias, but never let source order select a different root.
AUDIT_DIR="${AUDIT_DIR:-$HOME/.local/share/datarim-orchestrate}"
DR_ORCH_STATE_DIR="${DR_ORCH_STATE_DIR:-${STATE_DIR:-$AUDIT_DIR/state}}"
STATE_DIR="$DR_ORCH_STATE_DIR"
export AUDIT_DIR DR_ORCH_STATE_DIR STATE_DIR
umask 077
mkdir -p "$AUDIT_DIR" "$DR_ORCH_STATE_DIR"

DRY_RUN=0
PANE_ID=""
UNKNOWN_PROMPT=0
UNKNOWN_TEXT=""
ACTIVE_TASK=""
while (( $# > 0 )); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --pane)    PANE_ID="$2"; shift 2 ;;
    --task)    ACTIVE_TASK="$2"; shift 2 ;;
    --unknown-prompt)
               UNKNOWN_PROMPT=1
               # Optional inline text; otherwise pane capture supplies it.
               if [[ "${2:-}" =~ ^-- ]] || [[ -z "${2:-}" ]]; then
                 shift
               else
                 UNKNOWN_TEXT="$2"; shift 2
               fi
               ;;
    -h|--help) cat <<USAGE
usage: dr-orchestrate run [--dry-run] [--pane <pane_id>] [--task <TASK-ID>]
       dr-orchestrate run --unknown-prompt [text] [--task <TASK-ID>]

Phase 3 (TUNE-0166) adds trusted action execution plus actor/session-bound
Save-as-rule confirmation, 24-hour re-validation, and a seven-day rule TTL.
USAGE
               exit 0 ;;
    *)         echo "ERR: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

# shellcheck source=tmux_manager.sh
source "$DR_ORCH_DIR/scripts/tmux_manager.sh"
# shellcheck source=security.sh
source "$DR_ORCH_DIR/scripts/security.sh"
# shellcheck source=secrets_backend.sh
source "$DR_ORCH_DIR/scripts/secrets_backend.sh"
# shellcheck source=audit_sink.sh
source "$DR_ORCH_DIR/scripts/audit_sink.sh"
# shellcheck source=semantic_parser.sh
source "$DR_ORCH_DIR/scripts/semantic_parser.sh"
# shellcheck source=bot_interaction_dispatcher.sh
source "$DR_ORCH_DIR/scripts/bot_interaction_dispatcher.sh"
# shellcheck source=learned_rules.sh
source "$DR_ORCH_DIR/scripts/learned_rules.sh"
USER_CONFIG_YAML="${DR_ORCH_USER_CONFIG:-$DR_ORCH_DIR/user-config.yaml}"
[[ -f "$USER_CONFIG_YAML" ]] && bot_interaction_load "$USER_CONFIG_YAML" || true

SESSION_NAME="${SESSION_NAME:-datarim}"
CONFIDENCE_THRESHOLD="${DR_ORCH_CONFIDENCE_THRESHOLD:-0.80}"

AUDIT_FILE="$AUDIT_DIR/audit-$(date -u +%Y-%m-%d).jsonl"
DR_ORCH_AUDIT_FILE="$AUDIT_FILE"
export DR_ORCH_AUDIT_FILE

trusted_action() {
  local action="$1"
  load_trusted_actions | jq -e --arg action "$action" 'index($action) != null' >/dev/null
}

snapshot_hint_for_task() {
  local task="$1" workspace="${DR_ORCH_WORKSPACE:-$PWD}" snapshot task_desc hint
  [[ "$task" =~ ^[A-Z]+-[0-9]+$ ]] || return 1
  snapshot="$workspace/datarim/snapshots/$task.snapshot.md"
  task_desc="$workspace/datarim/tasks/$task-task-description.md"
  [[ -f "$snapshot" && ! -L "$snapshot" && -f "$task_desc" && ! -L "$task_desc" ]] || return 1
  grep -q "^task_id: $task$" "$snapshot" || return 1
  grep -qE '^stage: (init|prd|plan|design|do|qa|verify|compliance|archive)$' "$snapshot" || return 1
  hint="$(awk '$1=="recommended_next:" {print $2; exit}' "$snapshot")"
  [[ "$hint" =~ ^/dr-[a-z-]+$ ]] || return 1
  printf '%s\n' "$hint"
}

# execute_selected_action <action> <pane> <cycle_id> <confidence> <intent> <propose>
# The write-ahead checkpoint is mandatory. A test seam records the action
# instead of touching tmux, while production uses the existing safe pane path.
execute_selected_action() {
  local action="$1" pane="$2" cycle_id="$3" confidence="$4" intent="$5"
  local should_propose="${6:-0}"
  trusted_action "$action" || return 3
  local payload
  payload="$(jq -n -c --arg command "$action" '{command:$command}')"
  bash "$DR_ORCH_DIR/scripts/action_gate.sh" gate \
    --action framework_command --payload "$payload" >/dev/null || return 10
  check_cooldown "$pane" decision 2>/dev/null || return 11
  emit "$AUDIT_FILE" "$(make_cycle_checkpoint prepare "$cycle_id" "$SESSION_NAME" "$pane" "$action" pending)" \
    || return 12
  local rc=0
  if [[ -n "${DR_ORCH_ACTION_EXECUTOR_LOG:-}" ]]; then
    printf '%s\n' "$action" >> "$DR_ORCH_ACTION_EXECUTOR_LOG" || rc=$?
  else
    pane_send "$pane" "$action" || rc=$?
  fi
  emit "$AUDIT_FILE" "$(make_cycle_checkpoint terminal "$cycle_id" "$SESSION_NAME" "$pane" "$action" pending "exit_$rc")" \
    || return 12
  if (( rc == 0 && should_propose == 1 )); then
    learned_rules_propose "$intent" "$action" "$confidence" \
      "${DR_ORCH_ACTOR:-${USER:-agent}}" "${DR_ORCH_SESSION_CONTEXT:-$SESSION_NAME}" \
      >/dev/null 2>&1 || true
  fi
  return "$rc"
}

# resolve_and_route <pane_text> <pane_id> <start_ms> — Phase 2 unknown-prompt
# handler. Calls subagent_resolver.sh, gates on confidence threshold, either
# emits an audit v2 record with outcome=resolved or routes to escalation.
resolve_and_route() {
  local text="$1"; local pane="$2"; local start_ms="$3"
  local resolver_json conf action action_kind action_payload backend_used model end_ms dur hint=""
  if [[ -n "$ACTIVE_TASK" ]]; then hint="$(snapshot_hint_for_task "$ACTIVE_TASK" 2>/dev/null || true)"; fi
  if [[ -n "$hint" ]]; then
    resolver_json="$(bash "$DR_ORCH_DIR/scripts/subagent_resolver.sh" resolve --hint "$hint" -- "$text" 2>/dev/null || true)"
  else
    resolver_json="$(bash "$DR_ORCH_DIR/scripts/subagent_resolver.sh" resolve "$text" 2>/dev/null || true)"
  fi
  if [[ -z "$resolver_json" ]]; then
    resolver_json='{"action":"","confidence":0,"reason":"resolver_failed","backend_used":"none","subagent_model":""}'
  fi
  conf="$(printf '%s' "$resolver_json" | jq -r '.confidence // 0')"
  action="$(printf '%s' "$resolver_json" | jq -r '.action // ""')"
  action_kind="$(printf '%s' "$resolver_json" | jq -r '.action_kind // ""')"
  action_payload="$(printf '%s' "$resolver_json" | jq -c '.action_payload // {}')"
  backend_used="$(printf '%s' "$resolver_json" | jq -r '.backend_used // ""')"
  model="$(printf '%s' "$resolver_json" | jq -r '.subagent_model // ""')"
  end_ms="$(now_ms)"
  dur=$(( end_ms - start_ms ))
  local reason; reason="$(printf '%s' "$resolver_json" | jq -r '.reason // ""')"

  local pass=0
  awk -v c="$conf" -v t="$CONFIDENCE_THRESHOLD" 'BEGIN{ exit !(c+0 >= t+0) }' && pass=1

  if (( pass )); then
    [[ -n "$action_kind" ]] || action_kind="framework_command"
    if [[ -n "$action_kind" ]]; then
      local gate_rc
      set +e
      bash "$DR_ORCH_DIR/scripts/action_gate.sh" gate \
        --action "$action_kind" --payload "$action_payload" >/dev/null
      gate_rc=$?
      set -e
      if (( gate_rc != 0 )); then
        DR_ORCH_PROMPT_TEXT="$text" \
          bash "$DR_ORCH_DIR/scripts/escalation_backend.sh" emit "$resolver_json" "$pane" || true
        local gate_evt
        gate_evt="$(make_event_v2 "$text" "$action" "$gate_rc" "$dur" "$pane" \
          "$conf" "$model" "$backend_used" "${DR_ORCH_ESCALATION_BACKEND:-mock}" \
          "escalate" "escalated_space_policy" "space autonomy gate denied action")"
        emit "$AUDIT_FILE" "$gate_evt"
        echo "dr-orchestrate: escalate | action_kind=$action_kind | reason=space_policy"
        return 0
      fi
    fi
    local outcome="resolved" cycle_id
    cycle_id="$(hash_sha256 "$start_ms:$pane:$text")"
    if ! execute_selected_action "$action" "$pane" "$cycle_id" "$conf" "$text" 1; then
      outcome="blocked_execution"
    fi
    local evt
    evt="$(make_event_v2 "$text" "$action" 0 "$dur" "$pane" \
            "$conf" "$model" "$backend_used" "" "resolve" "$outcome" "$reason")"
    emit "$AUDIT_FILE" "$evt"
    echo "dr-orchestrate: resolve | action=$action | confidence=$conf | backend=$backend_used | outcome=$outcome"
    return 0
  fi

  # Below threshold → escalate. Resolver may have returned chain_exhausted (0)
  # or a low-confidence guess; either way the event is logged with the resolver
  # metadata for traceability.
  DR_ORCH_PROMPT_TEXT="$text" \
    bash "$DR_ORCH_DIR/scripts/escalation_backend.sh" emit "$resolver_json" "$pane" || true
  local esc_backend="${DR_ORCH_ESCALATION_BACKEND:-mock}"
  local evt
  evt="$(make_event_v2 "$text" "$action" 0 "$dur" "$pane" \
          "$conf" "$model" "$backend_used" "$esc_backend" "escalate" "escalated" "$reason")"
  emit "$AUDIT_FILE" "$evt"
  echo "dr-orchestrate: escalate | confidence=$conf | escalation=$esc_backend | backend=$backend_used"
}

if (( DRY_RUN )); then
  echo "dr-orchestrate: dry-run | bash=$BASH_VERSION | tmux=$(tmux -V 2>/dev/null || echo 'absent') | session=$SESSION_NAME"
  evt="$(make_event "dry-run cycle" "dr-orchestrate run --dry-run" 0 0 "${PANE_ID:-none}")"
  emit "$AUDIT_FILE" "$evt"
  exit 0
fi

if (( UNKNOWN_PROMPT )); then
  PANE_ID="${PANE_ID:-${SESSION_NAME}:0.0}"
  # Inbox-poll branch: dequeue oldest inbox message before falling back to
  # pane_capture. Inbox directory is written by orchestrator-input-handler.sh
  # (async path). Files are named <ulid>.json and sorted lexicographically
  # (ULID sort = arrival order). On dequeue the file is removed atomically.
  _DR_ORCH_INBOX_DIR="${DR_ORCH_INBOX_DIR:-$HOME/.local/share/datarim-orchestrate/inbox}"
  if [[ -z "$UNKNOWN_TEXT" ]] && [[ -d "$_DR_ORCH_INBOX_DIR" ]]; then
    oldest="$(ls "$_DR_ORCH_INBOX_DIR"/*.json 2>/dev/null | sort | head -1 || true)"
    if [[ -n "$oldest" ]] && [[ -f "$oldest" ]]; then
      _inbox_body="$(cat "$oldest")"
      _inbox_cmd="$(printf '%s' "$_inbox_body" | jq -r '.command // empty' 2>/dev/null || true)"
      if [[ -n "$_inbox_cmd" ]]; then
        UNKNOWN_TEXT="$_inbox_cmd"
        rm -f "$oldest"
      fi
    fi
  fi
  if [[ -z "$UNKNOWN_TEXT" ]]; then
    UNKNOWN_TEXT="$(pane_capture "$PANE_ID" 2>/dev/null || true)"
  fi
  start_ms=$(now_ms)
  resolve_and_route "$UNKNOWN_TEXT" "$PANE_ID" "$start_ms"
  exit 0
fi

tmux_version_check
session_recover "$SESSION_NAME"

PANE_ID="${PANE_ID:-${SESSION_NAME}:0.0}"

learned_rules_maintenance >/dev/null 2>&1 || true
recover_latest_cycle_checkpoint "$AUDIT_DIR" "$AUDIT_FILE" "$SESSION_NAME" "$PANE_ID" || true

start_ms=$(now_ms)
text="$(pane_capture "$PANE_ID" 2>/dev/null || true)"
decision="$(parse "$text")"
confidence="$(printf '%s' "$decision" | jq -r '.confidence')"
end_ms=$(now_ms)
dur=$(( end_ms - start_ms ))

# Rule-hit path: emit schema-v2 event so resolved rule-hits enter the
# label-aware metric (schema_version==2 filter in measure script).
# stage=parse, outcome=resolved. expected_outcome read from env (soak driver).
# Routing unchanged — rule-hit still resolves locally without subagent call.
if [[ "$confidence" != "0" ]]; then
  selected_action="$(printf '%s' "$decision" | jq -r '.action // ""')"
  local_outcome="resolved"
  cycle_id="$(hash_sha256 "$start_ms:$PANE_ID:$text")"
  if ! execute_selected_action "$selected_action" "$PANE_ID" "$cycle_id" "$confidence" "$text" 0; then
    local_outcome="blocked_execution"
  fi
  evt="$(make_event_v2 "$text" "$selected_action" 0 "$dur" "$PANE_ID" \
          "$confidence" "" "" "" "parse" "$local_outcome" "rule_hit")"
  emit "$AUDIT_FILE" "$evt"
  echo "dr-orchestrate run | confidence=$confidence | pane=$PANE_ID | dur=${dur}ms | outcome=$local_outcome | $(date -u +%FT%TZ)"
  exit 0
fi

# Phase-2 rule-miss path: emit v2 parse-miss audit + fall through to resolver.
miss_evt="$(make_event_v2 "$text" "dr-orchestrate run" 0 "$dur" "$PANE_ID" \
            0 "" "" "" "parse" "miss" "rule_phase2_miss")"
emit "$AUDIT_FILE" "$miss_evt"

resolve_and_route "$text" "$PANE_ID" "$start_ms"
exit 0
