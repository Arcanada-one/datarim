#!/usr/bin/env bats

# test-immutability-rule.bats — verify the Test Immutability Rule section
# exists in tdd-discipline.md with the named antipattern.

setup() {
    RUNTIME="${DATARIM_RUNTIME:-$HOME/.claude}"
    DISCIPLINE="$RUNTIME/skills/testing/tdd-discipline.md"
}

@test "tdd-discipline.md has Test Immutability Rule section" {
    run grep -c "Test Immutability Rule" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "tdd-discipline.md names the antipattern 'weakening the assertion'" {
    run grep -c "weakening the assertion" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "tdd-discipline.md includes V-AC parity in immutability section" {
    run grep -c "V-AC parity" "$DISCIPLINE"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
