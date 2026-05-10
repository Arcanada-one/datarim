#!/usr/bin/env bash
# cmd_run.sh — entry point for `dr-orchestrate run`.
# Phase 1 (TUNE-0164): single iteration, lean rule-based.
set -euo pipefail

[[ "${BASH_VERSINFO[0]}" -ge 4 ]] || { echo "ERR: bash 4+ required (have $BASH_VERSION)" >&2; exit 1; }

DR_ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DR_ORCH_DIR

DRY_RUN=0
PANE_ID=""
while (( $# > 0 )); do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --pane)    PANE_ID="$2"; shift 2 ;;
    -h|--help) cat <<USAGE
usage: dr-orchestrate run [--dry-run] [--pane <pane_id>]

Phase 1 lean tmux runner. Single iteration: capture pane, parse, log to audit.
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
export STATE_DIR
mkdir -p "$AUDIT_DIR" "$STATE_DIR"

if (( DRY_RUN )); then
  echo "dr-orchestrate: dry-run | bash=$BASH_VERSION | tmux=$(tmux -V 2>/dev/null || echo 'absent') | session=$SESSION_NAME"
  evt="$(make_event "dry-run cycle" "dr-orchestrate run --dry-run" 0 0 "${PANE_ID:-none}")"
  emit "$AUDIT_DIR/audit-$(date -u +%Y-%m-%d).jsonl" "$evt"
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

evt="$(make_event "$text" "dr-orchestrate run" 0 "$dur" "$PANE_ID")"
emit "$AUDIT_DIR/audit-$(date -u +%Y-%m-%d).jsonl" "$evt"

echo "dr-orchestrate run | confidence=$confidence | pane=$PANE_ID | dur=${dur}ms | $(date -u +%FT%TZ)"
exit 0
