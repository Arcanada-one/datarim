#!/usr/bin/env bash
# Write-ahead gate for operational actions before dr-orchestrate execution.
# Thin plugin entry-point that delegates to the core resolver, reading the core
# canonical fb-rules.yaml. Provenance in documentation/how-to/evolution-log.md.
set -euo pipefail

DR_ORCH_DIR="${DR_ORCH_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="$(cd "$DR_ORCH_DIR/../.." && pwd)"
RESOLVER="${DR_AUTONOMY_RESOLVER:-$REPO_ROOT/dev-tools/resolve-space-autonomy.sh}"

# Use the core canonical fb-rules.yaml unless the caller sets DR_AUTONOMY_RULES.
_CORE_FB_RULES="${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/rules/fb-rules.yaml"
if [[ -z "${DR_AUTONOMY_RULES:-}" ]]; then
  export DR_AUTONOMY_RULES="$_CORE_FB_RULES"
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
