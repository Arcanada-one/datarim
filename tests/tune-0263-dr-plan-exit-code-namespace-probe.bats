#!/usr/bin/env bats
#
# /dr-plan Step 6.5 "Exit-code namespace probe" regression guard (TUNE-0263,
# reassigned from TUNE-0259 due to ID collision — see archive-TUNE-0259.md).
#
# Contract: before a plan introduces a NEW exit code on a CLI binary, it must
# catalogue existing codes on the target source via grep, to avoid silently
# colliding with an already-documented exit code's meaning.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DR_PLAN_DOC="$REPO_ROOT/commands/dr-plan.md"

@test "T1: dr-plan.md contains 'Exit-code namespace probe' sub-bullet" {
    [ -f "$DR_PLAN_DOC" ]
    run grep -F "Exit-code namespace probe" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}

@test "T2: probe cites the grep-catalogue mechanic against the target source" {
    run grep -F 'grep -E "return [0-9]+|sys\.exit\([0-9]+\)" <target-source>' "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}

@test "T3: probe trigger is scoped to 'NEW exit code on a CLI binary'" {
    run grep -F "NEW exit code on a CLI binary" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}

@test "T4: probe bullet lives inside Step 6.5 Symbol Existence Check block" {
    awk '/^6\.5\./{flag=1} flag && /Exit-code namespace probe/{found=1} flag && /^7\./{exit} END{exit !found}' "$DR_PLAN_DOC"
}
