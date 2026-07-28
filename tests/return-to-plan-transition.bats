#!/usr/bin/env bats

# return-to-plan-transition.bats — verify the Return-to-Plan Transition is
# defined in tdd-discipline.md and wired into dr-do.md.

setup() {
    RUNTIME="${DATARIM_RUNTIME:-$HOME/.claude}"
    DISCIPLINE="$RUNTIME/skills/testing/tdd-discipline.md"
    DO_CMD="$RUNTIME/commands/dr-do.md"
}

@test "tdd-discipline.md defines Return-to-Plan Transition section" {
    run grep -c "Return-to-Plan Transition" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "tdd-discipline.md defines the trigger element" {
    run grep -c "Trigger:" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "tdd-discipline.md defines who decides" {
    run grep -c "Who decides" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "tdd-discipline.md defines where recorded" {
    run grep -c "Where it is recorded" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "tdd-discipline.md defines how resume" {
    run grep -c "How.*resumes" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-do.md has Step 7.5b Test/V-AC Change Escalation" {
    run grep -c "7.5b" "$DO_CMD"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-do.md routes to /dr-plan on return-to-plan" {
    run grep -c "/dr-plan {TASK-ID}" "$DO_CMD"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
