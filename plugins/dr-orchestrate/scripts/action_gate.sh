#!/usr/bin/env bash
# Write-ahead gate for operational actions before dr-orchestrate execution.
# Thin plugin entry-point that delegates to the core resolver. CORE-ONLY
# fb-rules resolution: the one-cycle deprecation fallback to a plugin-local
# copy was removed after consumers resynced to the core path (see
# documentation/how-to/evolution-log.md). Runtime install wins; the
# repo-relative core path covers checkout-only invocations.
set -euo pipefail

DR_ORCH_DIR="${DR_ORCH_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="$(cd "$DR_ORCH_DIR/../.." && pwd)"
RESOLVER="${DR_AUTONOMY_RESOLVER:-$REPO_ROOT/dev-tools/resolve-space-autonomy.sh}"

# Core canonical fb-rules only (runtime install first, repo-relative second).
_RUNTIME_FB_RULES="${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/rules/fb-rules.yaml"
_REPO_FB_RULES="$REPO_ROOT/dev-tools/rules/fb-rules.yaml"
if [[ -z "${DR_AUTONOMY_RULES:-}" ]]; then
  if [[ -f "$_RUNTIME_FB_RULES" ]]; then
    export DR_AUTONOMY_RULES="$_RUNTIME_FB_RULES"
  else
    export DR_AUTONOMY_RULES="$_REPO_FB_RULES"
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
