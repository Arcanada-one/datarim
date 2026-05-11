#!/usr/bin/env bash
# cmd_run.sh — entry point for `dr-orchestrate run`.
# Phase 1 (TUNE-0164): single iteration, lean rule-based.
set -euo pipefail

[[ "${BASH_VERSINFO[0]}" -ge 4 ]] || { echo "ERR: bash 4+ required (have $BASH_VERSION)" >&2; exit 1; }

DR_ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DR_ORCH_DIR

DRY_RUN=0
PANE_ID=""
UNKNOWN_PROMPT=0
UNKNOWN_TEXT=""
while (( $# > 0 )); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --pane)    PANE_ID="$2"; shift 2 ;;
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
usage: dr-orchestrate run [--dry-run] [--pane <pane_id>]
       dr-orchestrate run --unknown-prompt [text]

Phase 2 (TUNE-0165) adds subagent inference for parser misses: confidence-0
parses fall through to subagent_resolver.sh → autonomous-or-escalate, with
audit schema v2 emitted at each stage.
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

SESSION_NAME="${SESSION_NAME:-datarim}"
AUDIT_DIR="${AUDIT_DIR:-$HOME/.local/share/datarim-orchestrate}"
STATE_DIR="${STATE_DIR:-$AUDIT_DIR/state}"
CONFIDENCE_THRESHOLD="${DR_ORCH_CONFIDENCE_THRESHOLD:-0.80}"
export STATE_DIR
mkdir -p "$AUDIT_DIR" "$STATE_DIR"

AUDIT_FILE="$AUDIT_DIR/audit-$(date -u +%Y-%m-%d).jsonl"

# resolve_and_route <pane_text> <pane_id> <start_ms> — Phase 2 unknown-prompt
# handler. Calls subagent_resolver.sh, gates on confidence threshold, either
# emits an audit v2 record with outcome=resolved or routes to escalation.
resolve_and_route() {
  local text="$1"; local pane="$2"; local start_ms="$3"
  local resolver_json conf action backend_used model end_ms dur
  resolver_json="$(bash "$DR_ORCH_DIR/scripts/subagent_resolver.sh" resolve "$text" 2>/dev/null || true)"
  if [[ -z "$resolver_json" ]]; then
    resolver_json='{"action":"","confidence":0,"reason":"resolver_failed","backend_used":"none","subagent_model":""}'
  fi
  conf="$(printf '%s' "$resolver_json" | jq -r '.confidence // 0')"
  action="$(printf '%s' "$resolver_json" | jq -r '.action // ""')"
  backend_used="$(printf '%s' "$resolver_json" | jq -r '.backend_used // ""')"
  model="$(printf '%s' "$resolver_json" | jq -r '.subagent_model // ""')"
  end_ms="$(now_ms)"
  dur=$(( end_ms - start_ms ))
  local reason; reason="$(printf '%s' "$resolver_json" | jq -r '.reason // ""')"

  local pass=0
  awk -v c="$conf" -v t="$CONFIDENCE_THRESHOLD" 'BEGIN{ exit !(c+0 >= t+0) }' && pass=1

  if (( pass )); then
    local outcome="resolved"
    if ! check_cooldown "$pane" decision 2>/dev/null; then
      outcome="blocked_decision_cooldown"
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
  if [[ -z "$UNKNOWN_TEXT" ]]; then
    UNKNOWN_TEXT="$(pane_capture "$PANE_ID" 2>/dev/null || true)"
  fi
  start_ms=$(now_ms)
  resolve_and_route "$UNKNOWN_TEXT" "$PANE_ID" "$start_ms"
  exit 0
fi

tmux_version_check
session_init "$SESSION_NAME"

PANE_ID="${PANE_ID:-${SESSION_NAME}:0.0}"

start_ms=$(now_ms)
text="$(pane_capture "$PANE_ID" 2>/dev/null || true)"
decision="$(parse "$text")"
confidence="$(printf '%s' "$decision" | jq -r '.confidence')"
end_ms=$(now_ms)
dur=$(( end_ms - start_ms ))

# Phase-1 rule-hit path: emit v1 event (backward compatible).
if [[ "$confidence" != "0" ]]; then
  evt="$(make_event "$text" "dr-orchestrate run" 0 "$dur" "$PANE_ID")"
  emit "$AUDIT_FILE" "$evt"
  echo "dr-orchestrate run | confidence=$confidence | pane=$PANE_ID | dur=${dur}ms | $(date -u +%FT%TZ)"
  exit 0
fi

# Phase-2 rule-miss path: emit v2 parse-miss audit + fall through to resolver.
miss_evt="$(make_event_v2 "$text" "dr-orchestrate run" 0 "$dur" "$PANE_ID" \
            0 "" "" "" "parse" "miss" "rule_phase2_miss")"
emit "$AUDIT_FILE" "$miss_evt"

resolve_and_route "$text" "$PANE_ID" "$start_ms"
exit 0
