#!/usr/bin/env bats

# vac-deliverable-coverage.bats — verify the vac-deliverable-coverage rule
# is registered and detects a Component Breakdown artifact with no V-AC row.

setup() {
    RUNTIME="${DATARIM_RUNTIME:-$HOME/.claude}"
    LINT="$RUNTIME/dev-tools/dr-spec-lint.sh"
    RULES="$RUNTIME/dev-tools/dr-spec-rules.yaml"
    GATE="$RUNTIME/dev-tools/spec-graph-gate.sh"
}

@test "vac-deliverable-coverage rule is registered in dr-spec-rules.yaml" {
    run grep -c "vac-deliverable-coverage" "$RULES"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "vac-deliverable-coverage is in dr-spec-lint.sh rule list" {
    run grep -c "vac-deliverable-coverage" "$LINT"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "vac-deliverable-coverage is in spec-graph-gate.sh stage rule sets" {
    run grep -c "vac-deliverable-coverage" "$GATE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}
