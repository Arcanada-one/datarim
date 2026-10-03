#!/usr/bin/env bash
# plugin.sh — hook dispatcher for dr-orchestrate plugin.
# Pure routing; bash 3.2+ ok. The bash-4 floor lives in cmd_run.sh where the
# actual cycle work runs (V-AC-15 must answer get_autonomy from any host bash).
set -euo pipefail

if [[ -z "${DR_ORCH_DIR:-}" ]]; then
  DR_ORCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  export DR_ORCH_DIR
fi

dispatch() {
  local hook="$1"; shift || true
  case "$hook" in
    on_cycle)
      if [[ "${1:-}" == "--dry-run" ]]; then
        echo "dr-orchestrate: on_cycle dispatch (dry-run)"
        return 0
      fi
      "$DR_ORCH_DIR/scripts/cmd_run.sh" "$@"
      ;;
    on_unknown_prompt)
      # TUNE-0165 M6: parser-miss escalation hook. Caller supplies the
      # already-captured pane text via --unknown-prompt; cmd_run.sh drives the
      # resolver + escalation chain.
      "$DR_ORCH_DIR/scripts/cmd_run.sh" --unknown-prompt "$@"
      ;;
    on_callback)
      # Transport-neutral seam used by Telegram/bot adapters. Live Telegram
      # HTTP transport remains outside this plugin phase.
      "$DR_ORCH_DIR/scripts/learned_rules.sh" consume_callback "$@"
      ;;
    on_tune_complete)
      "$DR_ORCH_DIR/scripts/learned_rules.sh" maintenance
      return 0
      ;;
    on_context_pressure)
      "$DR_ORCH_DIR/scripts/context_pressure_adapter.sh" "$@"
      ;;
    *)
      return 0
      ;;
  esac
}

# Plugin autonomy level. Returns a baseline integer for legacy callers;
# effective autonomy is resolved per-space at runtime via action_gate.sh
# (which delegates to dev-tools/resolve-space-autonomy.sh + space.yml §
# autonomy.policy). Full-autonomy spaces return "auto" from the gate and run
# all reversible actions without asking. See README.md § Autonomy Levels.
get_autonomy() { echo "4"; }

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    dispatch)     dispatch "$@" ;;
    get_autonomy) get_autonomy ;;
    *)            echo "usage: plugin.sh {dispatch <hook> [args] | get_autonomy}" >&2; exit 2 ;;
  esac
fi
