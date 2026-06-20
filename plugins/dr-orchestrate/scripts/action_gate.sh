#!/usr/bin/env bash
# Write-ahead gate for operational actions before dr-orchestrate execution.
set -euo pipefail

DR_ORCH_DIR="${DR_ORCH_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="$(cd "$DR_ORCH_DIR/../.." && pwd)"
RESOLVER="${DR_AUTONOMY_RESOLVER:-$REPO_ROOT/dev-tools/resolve-space-autonomy.sh}"
export DR_AUTONOMY_RULES="${DR_AUTONOMY_RULES:-$DR_ORCH_DIR/rules/fb-rules.yaml}"

gate() {
  "$RESOLVER" gate "$@"
}

command_name="${1:-}"
shift || true
case "$command_name" in
  gate) gate "$@" ;;
  *) echo "usage: action_gate.sh gate --action <kind> [--payload <json>]" >&2; exit 2 ;;
esac
