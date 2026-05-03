#!/usr/bin/env bats
# test-command-doc-coverage.bats — TUNE-0090 + TUNE-0091
#
# Original 4 assertions preserved:
#   1. Every dr-* in docs/commands.md     -> delegates to doc-fanout-lint
#   2. Every dr-* in CLAUDE.md            -> delegates to doc-fanout-lint
#   3. No obsolete /dr-reflect|/dr-security references (native)
#   4. code/datarim/documentation/ absent in framework repo (native)

setup() {
    REPO="$BATS_TEST_DIRNAME/.."
}

@test "every dr-* command file appears in docs/commands.md (doc-fanout linter)" {
    # Use a fixture config that targets only commands × docs/commands.md.
    CFG="$BATS_TEST_DIRNAME/fixtures/test-command-doc-coverage-commands.yml"
    run bash "$REPO/dev-tools/doc-fanout-lint.sh" --root "$REPO" --config "$CFG" --quiet
    [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "every dr-* command file is mentioned in CLAUDE.md (doc-fanout linter)" {
    CFG="$BATS_TEST_DIRNAME/fixtures/test-command-doc-coverage-claude.yml"
    run bash "$REPO/dev-tools/doc-fanout-lint.sh" --root "$REPO" --config "$CFG" --quiet
    [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "no obsolete /dr-reflect or /dr-security references in CLAUDE.md" {
    ! grep -qE '/dr-reflect|/dr-security' "$REPO/CLAUDE.md"
}

@test "code/datarim/documentation/ does not exist in framework repo" {
    [ ! -d "$REPO/documentation" ]
}
