#!/usr/bin/env bats

# tdd-discipline-wiring.bats — verify tdd-discipline.md is wired into the
# execution path (developer agent and /dr-do command).

setup() {
    REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "developer agent references tdd-discipline.md" {
    run grep -c "tdd-discipline" "$REPO_DIR/agents/developer.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "developer agent does NOT list testing skill as OPTIONAL" {
    run bash -c 'grep "OPTIONAL" "$1/agents/developer.md" | grep -c "testing/SKILL.md"' -- "$REPO_DIR"
    [ "$output" = "0" ]
}

@test "dr-do command Step 4 references tdd-discipline.md" {
    run grep -c "tdd-discipline" "$REPO_DIR/commands/dr-do.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
