#!/usr/bin/env bats
# test-command-doc-coverage.bats — TUNE-0090 + TUNE-0091
#
# Original 4 assertions preserved:
#   1. Every dr-* in documentation/reference/commands.md -> delegates to doc-fanout-lint
#   2. Every dr-* in CLAUDE.md            -> delegates to doc-fanout-lint
#   3. No obsolete /dr-reflect|/dr-security references (native)
#   4. documentation/ is the canonical docs root with the 4 Diátaxis categories (INFRA-0306,
#      2.49.0 — supersedes the pre-rename invariant that asserted documentation/ ABSENT)

setup() {
    REPO="$BATS_TEST_DIRNAME/.."
}

@test "every dr-* command file appears in documentation/reference/commands.md (doc-fanout linter)" {
    # Use a fixture config that targets only commands × documentation/reference/commands.md.
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

@test "documentation/ is the canonical docs root with the 4 Diátaxis categories" {
    # INFRA-0306 (2.49.0): documentation/ replaced docs/ as the canonical root.
    # Supersedes the prior invariant that asserted documentation/ ABSENT.
    [ -d "$REPO/documentation" ]
    [ -d "$REPO/documentation/tutorials" ]
    [ -d "$REPO/documentation/how-to" ]
    [ -d "$REPO/documentation/reference" ]
    [ -d "$REPO/documentation/explanation" ]
    # legacy docs/ must be gone
    [ ! -d "$REPO/docs" ]
}
