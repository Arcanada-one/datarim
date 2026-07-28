#!/usr/bin/env bats

# non-code-parity.bats — verify the dr-plan.md command carries non-code
# parity prose for checklist immutability and return-to-plan transition.

setup() {
    RUNTIME="${DATARIM_RUNTIME:-$HOME/.claude}"
    PLAN_CMD="$RUNTIME/commands/dr-plan.md"
}

@test "dr-plan.md references checklist immutability" {
    run grep -i -c "immutab" "$PLAN_CMD"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-plan.md references return-to-plan for checklist items" {
    run grep -i -c "return.to.plan\|Return.to.Plan" "$PLAN_CMD"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-plan.md names checklist scope reduction antipattern" {
    run grep -c "checklist scope reduction" "$PLAN_CMD"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
