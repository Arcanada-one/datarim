#!/usr/bin/env bash
#
# Run the bats surfaces that had no CI invocation at all.
#
# Until this existed, 92 of the repo's 344 tracked suites ran on nobody's
# machine but the author's: plugins/dr-orchestrate/tests (46, and
# dr-orchestrate-contract.yml only runs Schemathesis — it never calls bats),
# cli/tests (23, referenced by no workflow whatsoever), dev-tools/tests (22 of
# 29 — the other 7 are named individually in dev-tools-lint.yml), and
# tests/install-matrix (1, invisible because `bats <dir>` does not recurse).
#
# Two properties this script exists to guarantee, because a "wired" suite that
# silently executes nothing is the original defect wearing a green tick:
#
#   1. A glob that matches nothing FAILS. Every surface declares a floor; if
#      fewer suites than the floor are selected the run fails loudly instead of
#      reporting success over an empty set. The floor also catches silent
#      shrinkage (a suite deleted or renamed out of the glob), which a bare
#      "> 0" check would sail past.
#   2. Exclusions are declared HERE, next to the exclusion, each with its
#      reason. An excluded suite is a debt with an owner, not a silence.
#
# A floor rather than an exact count is deliberate: an exact count makes every
# added suite a red build until someone bumps a number, which trains people to
# bump the number without reading. The floor catches the failure modes that
# matter (zero matches, shrinkage) and stays quiet when coverage grows.
#
# Exit: 0 all selected suites pass, 1 any surface fails or under-selects.

set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1

overall=0

run_surface() {
    local label="$1" root="$2" floor="$3"
    shift 3
    local excludes=("$@")

    if [ ! -d "$root" ]; then
        echo "FAIL: ${label}: '${root}' does not exist — the glob can never match" >&2
        overall=1
        return 1
    fi

    local all=()
    mapfile -t all < <(find "$root" -type f -name '*.bats' | sort)

    local run=() f e skip
    for f in "${all[@]}"; do
        skip=0
        for e in ${excludes[@]+"${excludes[@]}"}; do
            [ "$f" = "$e" ] && { skip=1; break; }
        done
        [ "$skip" -eq 0 ] && run+=("$f")
    done

    echo "::group::${label} — ${#run[@]} selected / ${#all[@]} present / ${#excludes[@]} excluded (floor ${floor})"

    if [ "${#run[@]}" -lt "$floor" ]; then
        echo "FAIL: ${label} selected ${#run[@]} suite(s), below the declared floor of ${floor}." >&2
        echo "      Either the glob stopped matching or suites were removed." >&2
        echo "      Do not lower the floor to make this pass — find out what moved." >&2
        echo "::endgroup::"
        overall=1
        return 1
    fi

    if ! bats "${run[@]}"; then
        echo "FAIL: ${label} had failing suite(s)." >&2
        overall=1
    fi
    echo "::endgroup::"
}

# --- cli/tests ---------------------------------------------------------------
# 5 suites excluded. All five fail for ONE upstream defect, tracked as TUNE-0558:
# cli/subcommands/backlog.sh calls `flock --exclusive --timeout 5 LOCK -c CMD --
# ARG ARG`, but flock(1) accepts exactly one command argument after -c. The call
# therefore never runs the append, and the caller reports the failure as
# "STATE_MISMATCH: flock contention", which is not what happened. The bug is
# invisible on macOS, where flock(1) is absent and the python3 fallback runs.
# These are excluded because they are RED, not because they are unimportant —
# they are the highest-value thing this wiring found. Re-include them with the fix.
run_surface "cli/tests" "cli/tests" 18 \
    "cli/tests/backlog-add-collision.bats" \
    "cli/tests/accepted-risk-expiry.bats" \
    "cli/tests/tasks-move.bats" \
    "cli/tests/tmux-attach.bats" \
    "cli/tests/tmux-ls.bats"

# --- dev-tools/tests ---------------------------------------------------------
# 4 suites excluded, all failing on this base, tracked as TUNE-0558. They share
# a shape: spec-graph/lint fixtures that assert "clean fixture → exit 0" and no
# longer get 0, i.e. the linters have grown findings the fixtures predate.
# dev-tools-lint.yml separately runs 7 of these suites as a BLOCKING job; this
# surface covers the other 22 and does not duplicate those 7 by name — running
# them twice is harmless and cheaper than keeping two lists in sync.
run_surface "dev-tools/tests" "dev-tools/tests" 25 \
    "dev-tools/tests/dr-lint.bats" \
    "dev-tools/tests/dr-spec-lint.bats" \
    "dev-tools/tests/dr-verify-floor-spec.bats" \
    "dev-tools/tests/spec-graph-gate.bats"

# --- plugins/**/tests --------------------------------------------------------
# The whole point: dr-orchestrate ships 46 suites and dr-orchestrate-contract.yml
# never invoked bats once. 2 excluded, tracked as TUNE-0558:
#   test_resolver_history.bats  — asserts resolver history state this checkout
#                                 does not reproduce; needs triage, not a skip.
#   contract/outbound-redis.bats — needs a reachable Redis; there is none on the
#                                 hosted runner. This one is environmental and
#                                 may stay excluded permanently, but it says so.
run_surface "plugins" "plugins" 44 \
    "plugins/dr-orchestrate/tests/test_resolver_history.bats" \
    "plugins/dr-orchestrate/tests/contract/outbound-redis.bats"

exit "$overall"
