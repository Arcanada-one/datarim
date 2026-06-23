#!/usr/bin/env bash
# Write-ahead gate for operational actions before dr-orchestrate execution.
# Thin plugin entry-point that delegates to the core resolver. Prefers the
# core fb-rules.yaml; falls back to the local plugin copy during the
# deprecation window (one minor cycle — see docs/evolution-log.md).
set -euo pipefail

DR_ORCH_DIR="${DR_ORCH_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="$(cd "$DR_ORCH_DIR/../.." && pwd)"
RESOLVER="${DR_AUTONOMY_RESOLVER:-$REPO_ROOT/dev-tools/resolve-space-autonomy.sh}"

# Prefer core path; fall back to plugin-local copy when core is absent.
_CORE_FB_RULES="${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/rules/fb-rules.yaml"
_LOCAL_FB_RULES="$DR_ORCH_DIR/rules/fb-rules.yaml"
if [[ -z "${DR_AUTONOMY_RULES:-}" ]]; then
  if [[ -f "$_CORE_FB_RULES" ]]; then
    export DR_AUTONOMY_RULES="$_CORE_FB_RULES"
  else
    export DR_AUTONOMY_RULES="$_LOCAL_FB_RULES"
  fi
fi

gate() {
  "$RESOLVER" gate "$@"
}

command_name="${1:-}"
shift || true
case "$command_name" in
  gate) gate "$@" ;;
  *) echo "usage: action_gate.sh gate --action <kind> [--payload <json>]" >&2; exit 2 ;;
esac
