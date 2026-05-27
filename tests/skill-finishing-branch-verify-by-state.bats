#!/usr/bin/env bats
#
# Regression: skills/finishing-a-development-branch/SKILL.md MUST carry the
# verify-by-state rule for git push — SHA-equality of local HEAD vs upstream
# tracking ref, not stdout text parsing.
#
# Class of incident: hook wrappers (token reducers, lint filters, terminal
# multiplexers) frequently truncate the canonical `To <repo>` push marker in
# stdout. Agents that gate next-step decisions on the marker text wait on
# already-successful pushes. SHA-equality is invariant under stdout transforms.

SKILL="${BATS_TEST_DIRNAME}/../skills/finishing-a-development-branch/SKILL.md"

@test "skill file exists" {
    [ -f "$SKILL" ]
}

@test "skill carries rev-parse @{u} verify-by-state rule" {
    run grep -cE 'rev-parse "?@\{u\}"?' "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "skill carries local HEAD vs upstream SHA comparison" {
    run grep -cE 'rev-parse HEAD' "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "skill warns against gating on stdout text" {
    run grep -cE 'stdout|To <repo>' "$SKILL"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
