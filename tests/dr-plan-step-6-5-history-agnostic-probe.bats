#!/usr/bin/env bats
# TUNE-0283 — Step 6.5 History-agnostic runtime-body probe contract regression guard.
# Shifts the task-ID-provenance / phantom-path gate left from /dr-qa & /dr-compliance
# to /dr-plan Step 6.5, before approve. Anchor-based extraction (robust to bullet
# relocation, BSD vs GNU sed/awk).

DR_PLAN="$BATS_TEST_DIRNAME/../commands/dr-plan.md"
GATE_DOC="$BATS_TEST_DIRNAME/../skills/evolution/history-agnostic-gate.md"

# Extract the bullet block: from header "History-agnostic runtime-body probe" to
# next sibling bullet (line starting with 4-space-indent `-   **`). tolower() for
# portability across BSD awk (macOS) and GNU awk (Linux/CI).
bullet_block() {
    awk 'tolower($0) ~ /history-agnostic runtime-body probe/ {flag=1; print; next}
         flag && /^    -   \*\*/ {exit}
         flag {print}' "$DR_PLAN"
}

@test "Step 6.5 contains 'History-agnostic runtime-body probe' bullet" {
    run grep -ci 'History-agnostic runtime-body probe' "$DR_PLAN"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "probe bullet is MANDATORY and scoped to shipped runtime bodies" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"MANDATORY"* ]]
    [[ "$block" == *"skills/"* ]]
    [[ "$block" == *"agents/"* ]]
    [[ "$block" == *"commands/"* ]]
    [[ "$block" == *"templates/"* ]]
}

@test "probe bullet reuses the history-agnostic-gate contract" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"history-agnostic-gate"* ]]
}

@test "probe bullet reuses the plan-path-validator skill (path exists/deprecation ladder)" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"plan-path-validator"* ]]
}

@test "probe bullet frames the shift-left rationale (caught at plan, not /dr-qa)" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    local block_flat; block_flat=$(printf '%s' "$block" | tr '\n' ' ')
    # Must name the downstream stage the gate is being shifted away from AND
    # bind it to a plan-time verdict.
    [[ "$block_flat" == *"/dr-qa"* ]]
    [[ "$block_flat" == *"planning defect"* ]]
}

@test "probe bullet demands an inline verdict annotation" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"nnotate"* ]] || [[ "$block" == *"nnotation"* ]]
}

@test "Transition Checkpoint carries a history-agnostic runtime-body item" {
    run grep -ci 'History-agnostic runtime-body probe' "$DR_PLAN"
    [ "$status" -eq 0 ]
    # header bullet (Step 6.5) + checklist item = at least 2 occurrences
    [ "$output" -ge 2 ]
}

@test "history-agnostic-gate.md Trigger list names dr-plan as a plan-time trigger" {
    run grep -c 'commands/dr-plan.md' "$GATE_DOC"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
    run grep -i 'dr-plan.md.*plan-time' "$GATE_DOC"
    [ "$status" -eq 0 ]
}
