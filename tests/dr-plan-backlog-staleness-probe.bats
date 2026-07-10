#!/usr/bin/env bats
# TUNE-0362 (part 1) — Backlog-brief staleness probe contract regression guard.
# Class A skill-update: /dr-plan Phase 4 first-action live-probe of a named
# file:mechanism claim in the backlog/init-task brief, so a stale brief
# (mechanism already migrated between backlog entry and plan time) does not
# ride unverified into the plan. Part 2 of TUNE-0362 (pre-archive-check
# schema-gate behaviour in shared workspaces) is Class B and out of scope here.

DR_PLAN="$BATS_TEST_DIRNAME/../commands/dr-plan.md"

# Extract the bullet block: from header to next sibling bullet (4-space-indent
# `-   **`). tolower() for portability across BSD awk (macOS) and GNU awk (Linux/CI).
bullet_block() {
    awk 'tolower($0) ~ /backlog-brief staleness probe/ {flag=1; print; next}
         flag && /^    -   \*\*/ {exit}
         flag {print}' "$DR_PLAN"
}

@test "Phase 4 contains 'Backlog-brief staleness probe' bullet" {
    run grep -ci 'Backlog-brief staleness probe' "$DR_PLAN"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "probe bullet is MANDATORY for L2+ and scoped to file:mechanism claims" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"MANDATORY"* ]]
    [[ "$block" == *"L2+"* ]]
    [[ "$block" == *"file:mechanism"* ]]
}

@test "probe bullet demands an inline confirmed-current/stale verdict" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"confirmed-current"* ]]
    [[ "$block" == *"stale"* ]]
}

@test "probe bullet carries no task-ID provenance (history-agnostic runtime body)" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    # No bare task-ID tokens (PREFIX-NNNN) inside the shipped bullet body.
    ! echo "$block" | grep -qE '\b[A-Z]{2,}-[0-9]{3,}\b'
}

@test "dr-plan.md passes the history-agnostic task-ID gate after the addition" {
    run bash "$BATS_TEST_DIRNAME/../scripts/task-id-gate.sh" "$DR_PLAN"
    [ "$status" -eq 0 ]
}

@test "dr-plan.md passes the stack-agnostic gate after the addition" {
    run bash "$BATS_TEST_DIRNAME/../scripts/stack-agnostic-gate.sh" "$DR_PLAN"
    [ "$status" -eq 0 ]
}
