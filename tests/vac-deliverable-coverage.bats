#!/usr/bin/env bats

# vac-deliverable-coverage.bats — verify the vac-deliverable-coverage rule
# is registered and referenced in the spec-lint toolchain.

setup() {
    REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    LINT="$REPO_DIR/dev-tools/dr-spec-lint.sh"
    RULES="$REPO_DIR/dev-tools/dr-spec-rules.yaml"
    GATE="$REPO_DIR/dev-tools/spec-graph-gate.sh"
}

@test "vac-deliverable-coverage rule is registered in dr-spec-rules.yaml" {
    run grep -c "vac-deliverable-coverage" "$RULES"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "vac-deliverable-coverage is referenced in dr-spec-lint.sh" {
    run grep -c "vac-deliverable-coverage" "$LINT"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "vac-deliverable-coverage is in spec-graph-gate.sh rule sets" {
    run grep -c "vac-deliverable-coverage" "$GATE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
