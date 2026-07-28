#!/usr/bin/env bats

# test-immutability-rule.bats — verify the Test Immutability Rule exists in
# tdd-discipline.md with the named antipattern.

setup() {
    REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    DISCIPLINE="$REPO_DIR/skills/testing/tdd-discipline.md"
}

@test "tdd-discipline.md has Test Immutability Rule section" {
    run grep -c "Test Immutability Rule" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "tdd-discipline.md names the antipattern 'weakening the assertion'" {
    run grep -c "weakening the assertion" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "tdd-discipline.md references V-AC in immutability context" {
    run grep -c "V-AC" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
