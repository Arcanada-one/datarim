#!/usr/bin/env bash
# gates/gate-bats.sh — fleet surface-guard tests must stay green for a candidate.
#
# argv[1] = candidate file (unused directly; the gate runs the suite that guards
# the fleet surface), argv[2] = skill level (unused). exit 0 = suite green,
# exit 1 = a fleet test failed, exit 0+skip-note = bats unavailable (env-gated).
#
# Rationale: a skill candidate ships into the fleet surface; the role-registry
# and level-resolver invariants must still hold. If bats is not installed
# (minimal env) the gate skips rather than fails — env-gated, never a false
# negative.
#
# IMPORTANT: this gate runs ONLY the surface-guard suites (role-registry,
# level-resolver). It MUST NOT run the evolution plugin's own bats files —
# test-fleet-evolution-gates.bats exercises run-all-gates, which calls this
# gate, which would recurse infinitely.

set -o pipefail

REPO_ROOT="${DR_FLEET_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"

main() {
    if ! command -v bats >/dev/null 2>&1; then
        echo "gate-bats: bats not installed — skipping (env-gated)" >&2
        exit 0
    fi

    # Surface-guard suite ONLY: fleet registry + level resolver. Never include
    # the evolution plugin's own tests (recursion — see header note).
    local suite=()
    local t
    for t in "$REPO_ROOT"/tests/test-role-registry.bats \
             "$REPO_ROOT"/tests/test-level-resolver.bats; do
        [ -f "$t" ] && suite+=("$t")
    done

    if [ "${#suite[@]}" -eq 0 ]; then
        echo "gate-bats: no fleet test files found — skipping" >&2
        exit 0
    fi

    if bats "${suite[@]}" >/dev/null 2>&1; then
        exit 0
    fi
    echo "gate-bats: fleet bats suite is not green" >&2
    exit 1
}

main "$@"
