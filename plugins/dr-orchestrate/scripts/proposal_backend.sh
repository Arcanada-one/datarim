#!/usr/bin/env bash
# Idempotent local delivery queue backend for learned-rule approval callbacks.

set -euo pipefail

PROPOSAL_BACKEND_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${DR_ORCH_DIR:=$(cd "$PROPOSAL_BACKEND_SCRIPT_DIR/.." && pwd)}"
export DR_ORCH_DIR
# shellcheck source=/dev/null
source "$PROPOSAL_BACKEND_SCRIPT_DIR/lib/learned-rules-store.sh"

proposal_backend_main() {
    local command=${1-}
    case "$command" in
        emit)
            [[ $# -eq 2 ]] || return 2
            learned_rules_enqueue "$2"
            ;;
        *)
            learned_rules_error 'usage: proposal_backend.sh emit <proposal-id>'
            return 2
            ;;
    esac
}

proposal_backend_main "$@"
