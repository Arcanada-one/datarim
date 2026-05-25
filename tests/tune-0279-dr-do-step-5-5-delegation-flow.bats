#!/usr/bin/env bats
#
# /dr-do Step 5.5 «OPERATOR-MANDATED DELEGATION FLOW» regression guard
# (absorbed TUNE-0277 → TUNE-0279 Phase A V-AC-A8).
#
# Stage-rule contract: commands/dr-do.md MUST keep the operator-mandated
# delegation section AND the Implementation Notes recording requirement.
# /dr-qa Layer 3b cross-checks the «one line per delegated artefact» line
# against touched files — silently dropping the rule would let token-economy
# violations land without a paper trail.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DR_DO_DOC="$REPO_ROOT/commands/dr-do.md"

@test "T1: dr-do.md contains 'OPERATOR-MANDATED DELEGATION FLOW' Step 5.5 header" {
    [ -f "$DR_DO_DOC" ]
    run grep -F "OPERATOR-MANDATED DELEGATION FLOW" "$DR_DO_DOC"
    [ "$status" -eq 0 ]
}

@test "T2: dr-do.md requires § Implementation Notes recording for each delegated artefact" {
    run grep -F "Record the delegation invocation in" "$DR_DO_DOC"
    [ "$status" -eq 0 ]
    run grep -F "§ Implementation Notes" "$DR_DO_DOC"
    [ "$status" -eq 0 ]
    run grep -F "one line per delegated artefact" "$DR_DO_DOC"
    [ "$status" -eq 0 ]
}
