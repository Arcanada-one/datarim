#!/usr/bin/env bats

# return-to-plan-transition.bats — verify the Return-to-Plan transition is
# defined in tdd-discipline.md and wired into dr-do.md.

setup() {
    REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    DISCIPLINE="$REPO_DIR/skills/testing/tdd-discipline.md"
    DR_DO="$REPO_DIR/commands/dr-do.md"
}

@test "tdd-discipline.md defines Return-to-Plan Transition section" {
    run grep -c "Return-to-Plan Transition" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "tdd-discipline.md defines the trigger element" {
    run grep -c "Trigger" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "tdd-discipline.md defines who decides" {
    run grep -ci "who decides\|operator" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "tdd-discipline.md defines where recorded" {
    run grep -c "recorded" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "tdd-discipline.md defines how resume" {
    run grep -c "resumes" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-do.md has Step 7.5b Test/V-AC Change Escalation" {
    run grep -c "TEST/V-AC CHANGE ESCALATION" "$DR_DO"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-do.md routes to /dr-plan on return-to-plan" {
    run grep -c "/dr-plan {TASK-ID}" "$DR_DO"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
