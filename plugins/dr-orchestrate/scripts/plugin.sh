#!/usr/bin/env bash
# plugin.sh — hook dispatcher for dr-orchestrate plugin (Phase 1, TUNE-0164).
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
    on_tune_complete)
      echo "dr-orchestrate: on_tune_complete noop (Phase 3 hook)"
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}

# Plugin autonomy level. TUNE-0165 bumps L1 (manual) → L2 (assisted).
get_autonomy() { echo "2"; }

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    dispatch)     dispatch "$@" ;;
    get_autonomy) get_autonomy ;;
    *)            echo "usage: plugin.sh {dispatch <hook> [args] | get_autonomy}" >&2; exit 2 ;;
  esac
fi
