#!/usr/bin/env bats
#
# /dr-do Step 7 ACTION — lint-on-the-spot regression guard (TUNE-0260).
# Linter must run after each TDD Loop code-change step, not just be
# deferred to /dr-compliance (reflection-TUNE-0258 § Class A A2 — 3
# ruff-notation lint findings required a separate fixup commit c-208c027
# because linting only happened at compliance time).

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DR_DO_DOC="$REPO_ROOT/commands/dr-do.md"

@test "T1: dr-do.md Step 7 ACTION contains 'Lint-on-the-spot' sub-bullet" {
    [ -f "$DR_DO_DOC" ]
    run grep -F "Lint-on-the-spot" "$DR_DO_DOC"
    [ "$status" -eq 0 ]
}

@test "T2: lint rule triggers after each TDD Loop code-change step" {
    run grep -F "MANDATORY after each TDD Loop code-change step" "$DR_DO_DOC"
    [ "$status" -eq 0 ]
}

@test "T3: lint rule forbids deferring lint debt to /dr-compliance" {
    run grep -F "do not carry lint debt forward to \`/dr-compliance\`" "$DR_DO_DOC"
    [ "$status" -eq 0 ]
}

@test "T4: lint rule names linter recipes across ecosystems, wrapped in gate:example-only" {
    awk '/Lint-on-the-spot/{flag=1} flag && /cargo clippy/{found_clippy=1} flag && /eslint <changed-files>/{found_eslint=1} flag && /ruff check <changed-files>/{found_ruff=1} flag && /<!-- \/gate:example-only -->/{exit} END{exit !(found_clippy && found_eslint && found_ruff)}' "$DR_DO_DOC"
}

@test "T5: lint-on-the-spot bullet sits inside Step 7 ACTION, before Step 7.5" {
    awk '/^7\.  \*\*ACTION\*\*/{flag=1} flag && /Lint-on-the-spot/{found=1} flag && /^7\.5/{exit} END{exit !found}' "$DR_DO_DOC"
}
