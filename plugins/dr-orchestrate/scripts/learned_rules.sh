#!/usr/bin/env bash
# Public learned-rule lifecycle API and CLI.

LEARNED_RULES_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${DR_ORCH_DIR:=$(cd "$LEARNED_RULES_SCRIPT_DIR/.." && pwd)}"
export DR_ORCH_DIR
# shellcheck source=/dev/null
source "$LEARNED_RULES_SCRIPT_DIR/lib/learned-rules-store.sh"

learned_rules_propose() {
    local intent=${1-} action=${2-} confidence=${3-} actor=${4-} session=${5-}
    local proposal_id rc
    [[ $# -eq 5 ]] || {
        learned_rules_error 'propose requires intent action confidence actor session'
        return 2
    }
    if proposal_id=$(learned_rules_create_proposal "$intent" "$action" "$confidence" "$actor" "$session"); then
        rc=0
    else
        rc=$?
    fi
    [[ -n "$proposal_id" ]] && printf '%s\n' "$proposal_id"
    (( rc == 0 )) || return "$rc"
    bash "$LEARNED_RULES_SCRIPT_DIR/proposal_backend.sh" emit "$proposal_id" || return
    if [[ ${DR_ORCH_TEST_CRASH_POINT:-} = after_queue_enqueue ]]; then
        return 75
    fi
    learned_rules_mark_delivered "$proposal_id"
}

learned_rules_consume_callback() {
    [[ $# -eq 4 ]] || {
        learned_rules_error 'consume_callback requires id Y|N actor session'
        return 2
    }
    learned_rules_consume "$1" "$2" "$3" "$4"
}

learned_rules_maintenance() {
    [[ $# -eq 0 ]] || return 2
    learned_rules_store_maintenance
}

learned_rules_main() {
    local command=${1-}
    [[ $# -gt 0 ]] && shift
    case "$command" in
        propose)
            learned_rules_propose "$@"
            ;;
        consume_callback)
            learned_rules_consume_callback "$@"
            ;;
        maintenance)
            learned_rules_maintenance "$@"
            ;;
        *)
            learned_rules_error 'usage: learned_rules.sh propose <intent> <action> <confidence> <actor> <session> | consume_callback <id> <Y|N> <actor> <session> | maintenance'
            return 2
            ;;
    esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    set -euo pipefail
    learned_rules_main "$@"
fi
