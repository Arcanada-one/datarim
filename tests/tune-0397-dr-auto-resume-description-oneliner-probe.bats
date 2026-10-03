#!/usr/bin/env bats
# TUNE-0397 — /dr-auto resume description-vs-oneliner consistency probe
# regression guard. Prevents recurrence of VERD-0037 (a reused task ID left
# a stale task-description § Overview describing a different scope than the
# current tasks.md one-liner). Source: reflection-VERD-0037 Class B.

DR_AUTO="$BATS_TEST_DIRNAME/../commands/dr-auto.md"

bullet_block() {
    awk 'tolower($0) ~ /description-vs-oneliner consistency probe/ {flag=1; print; next}
         flag && /^     -   \*\*/ {exit}
         flag {print}' "$DR_AUTO"
}

@test "Resume mode step contains the description-vs-oneliner consistency probe" {
    run grep -ci 'Description-vs-oneliner consistency probe' "$DR_AUTO"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "probe is MANDATORY before /dr-do dispatch and cites task-description Overview" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"MANDATORY"* ]]
    [[ "$block" == *"task-description.md"* ]]
    [[ "$block" == *"Overview"* ]]
    [[ "$block" == *"one-liner"* ]]
}

@test "probe requires stopping to flag the operator on mismatch" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"STOP"* ]]
    [[ "$block" == *"flag"* ]]
}

@test "probe cites the resume-scope-drift precedent" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"prior resume incident"* ]]
}
