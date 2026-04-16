#!/usr/bin/env bats
#
# T1 (TUNE-0013): spec-regression tests for commands/dr-archive.md Step 0.5.
#
# Contract under test (v1.10.0 pipeline):
#   AC-1 / AC-2: /dr-archive gains a mandatory non-skippable Step 0.5 that
#   loads skills/reflecting.md and performs reflection for every archived task.
#
# Guards against silent weakening of the mandatory-reflection contract.

SPEC="${BATS_TEST_DIRNAME}/../commands/dr-archive.md"

@test "spec file exists" {
    [ -f "$SPEC" ]
}

@test "spec contains Step 0.5 section header" {
    run grep -F "0.5" "$SPEC"
    [ "$status" -eq 0 ]
}

@test "spec references skills/reflecting.md as the loaded skill" {
    run grep -F "skills/reflecting.md" "$SPEC"
    [ "$status" -eq 0 ]
}

@test "spec declares Step 0.5 as MANDATORY" {
    run grep -F "MANDATORY" "$SPEC"
    [ "$status" -eq 0 ]
}

@test "spec declares Step 0.5 as non-skippable" {
    run grep -iE "non-skippable|cannot be skipped|CANNOT be skipped" "$SPEC"
    [ "$status" -eq 0 ]
}

@test "spec explicitly rejects a --no-reflect opt-out flag" {
    run grep -iE "no.*--no-reflect|no.*opt-out|--no-reflect.*exist" "$SPEC"
    [ "$status" -eq 0 ]
}

@test "spec references evolution.md for Class A/B gate" {
    run grep -F "evolution.md" "$SPEC"
    [ "$status" -eq 0 ]
}

@test "spec lists reflection output paths (reflection doc + evolution-log)" {
    run grep -F "datarim/reflection/" "$SPEC"
    [ "$status" -eq 0 ]
}

@test "spec wires Step 0.5 failure-mode to STOP archive" {
    run grep -iE "failure.*STOP archive|STOP archive" "$SPEC"
    [ "$status" -eq 0 ]
}

@test "spec cites TUNE-0013 for pipeline v2 rationale" {
    run grep -F "TUNE-0013" "$SPEC"
    [ "$status" -eq 0 ]
}
