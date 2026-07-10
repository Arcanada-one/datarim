#!/usr/bin/env bats
#
# Spec-regression tests for commands/dr-publish.md (TUNE-0199).
#
# /dr-publish PREPARES ready-to-publish payloads (curl recipes, JSON bodies,
# Playwright steps) but MUST NOT dispatch — sending is hard-gated (public
# communications never auto-execute per the Autonomous Agent Operating Rules
# Mandate) and runs only via Publisher under operator approval.
#
# These tests guard against regression of the operator-UX trap where a prepared
# payload reads as a completed publish:
#   - the docstring/frontmatter states it prepares, does NOT dispatch
#   - the command output carries an explicit STOP indicator
#   - the STOP indicator / body cite the hard-gate rationale and mandate
#   - the CTA primary option is the manual dispatch, not next-stage routing
#
# If any of these fail, the "does-not-dispatch" contract has drifted.

REPO_ROOT="${BATS_TEST_DIRNAME}/.."
PUBLISH="${REPO_ROOT}/commands/dr-publish.md"

@test "dr-publish command file exists" {
    [ -f "$PUBLISH" ]
}

@test "frontmatter description states it does NOT dispatch" {
    run grep -F "does NOT dispatch" "$PUBLISH"
    [ "$status" -eq 0 ]
}

@test "docstring header line clarifies prepare-not-send" {
    run grep -Fi "PREPARES ready-to-publish payloads" "$PUBLISH"
    [ "$status" -eq 0 ]
}

@test "output contains an explicit STOP indicator" {
    run grep -F "STOP indicator (mandatory" "$PUBLISH"
    [ "$status" -eq 0 ]
    run grep -F "⛔ STOP" "$PUBLISH"
    [ "$status" -eq 0 ]
}

@test "STOP indicator states nothing has been published yet" {
    run grep -F "did NOT send them" "$PUBLISH"
    [ "$status" -eq 0 ]
}

@test "output mentions the hard-gate rationale (public communications never auto-execute)" {
    run grep -Fi "hard-gated" "$PUBLISH"
    [ "$status" -eq 0 ]
    run grep -F "public communications" "$PUBLISH"
    [ "$status" -eq 0 ]
}

@test "output cites the Autonomous Agent mandate as the hard-gate source" {
    run grep -F "documentation/mandates/autonomous-agents.md" "$PUBLISH"
    [ "$status" -eq 0 ]
}

@test "output routes actual dispatch through Publisher only" {
    run grep -F "Projects/Publisher/code/arcanada-publisher" "$PUBLISH"
    [ "$status" -eq 0 ]
}

@test "CTA option 1 is the manual dispatch, not next-stage routing" {
    run grep -Fi "CTA option 1 (primary) is ALWAYS the manual dispatch" "$PUBLISH"
    [ "$status" -eq 0 ]
}
