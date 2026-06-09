#!/usr/bin/env bash
# gates/run-all-gates.sh — run every constraint gate against a candidate (fail-closed).
#
# argv[1] = candidate file (SKILL.md), argv[2] = skill level (l1-basic ...).
# exit 0 only if EVERY gate passes; exit 1 if any gate fails; exit 2 usage.
# Fail-closed: an unknown gate exit (>=2) is treated as a failure.

set -o pipefail

GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { echo "Usage: $(basename "$0") <candidate-file> <skill-level>" >&2; }

main() {
    local candidate=${1:-}
    local level=${2:-}
    [ -n "$candidate" ] && [ -n "$level" ] || { usage; exit 2; }
    [ -f "$candidate" ] || { echo "run-all-gates: file not found: $candidate" >&2; exit 2; }

    local gate rc failed=0
    for gate in "$GATES_DIR"/gate-*.sh; do
        [ -f "$gate" ] || continue
        "$gate" "$candidate" "$level"
        rc=$?
        if [ "$rc" -ne 0 ]; then
            echo "run-all-gates: FAIL $(basename "$gate") (exit $rc)" >&2
            failed=1
        fi
    done

    [ "$failed" -eq 0 ] || exit 1
    exit 0
}

main "$@"
