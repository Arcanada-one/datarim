#!/usr/bin/env bats

setup() {
  export ROOT="$BATS_TEST_DIRNAME/.."
  export COMMAND="$ROOT/commands/dr-archive.md"
  export README="$ROOT/dev-tools/README.md"
}

line_of() {
  grep -nF "$1" "$COMMAND" | head -n 1 | cut -d: -f1
}

@test "archive command documents explicit default-off option precedence" {
  grep -q -- '--auto-commit' "$COMMAND"
  grep -q -- '--no-auto-commit' "$COMMAND"
  grep -q 'default-off' "$COMMAND"
  grep -q 'negative override wins' "$COMMAND"
}

@test "prepare occurs after clean-git gate and before archive mutations" {
  clean="$(line_of 'PRE-ARCHIVE CLEAN-GIT CHECK')"
  prepare="$(line_of 'archive-auto-commit.sh" prepare')"
  reflect="$(line_of 'REFLECT')"
  [ "$clean" -lt "$prepare" ]
  [ "$prepare" -lt "$reflect" ]
}

@test "final commit occurs after snapshot, archive write, and task cleanup" {
  snapshot="$(line_of 'STAGE-SNAPSHOT MOVE-TO-ARCHIVE')"
  archive="$(line_of 'Create archive document with:')"
  cleanup="$(line_of 'REMOVE FROM tasks.md')"
  commit="$(line_of 'archive-auto-commit.sh" commit')"
  [ "$snapshot" -lt "$commit" ]
  [ "$archive" -lt "$commit" ]
  [ "$cleanup" -lt "$commit" ]
}

@test "wiring passes only canonical archive and optional snapshot roles" {
  grep -q -- '--archive "documentation/archive/<area>/archive-{TASK-ID}.md"' "$COMMAND"
  grep -q -- '--snapshot "documentation/archive/<area>/snapshots/{TASK-ID}-final-stage.md"' "$COMMAND"
  run grep -E 'archive-auto-commit\.sh" commit.*(tasks\.md|activeContext|backlog|reflection|plan)' "$COMMAND"
  [ "$status" -eq 1 ]
}

@test "policy refusal never bypasses or reverses archive hard gates" {
  grep -q 'auto-commit refusal does not undo or misreport the completed archive' "$COMMAND"
  grep -q 'pre-archive-check.sh' "$COMMAND"
  grep -q 'check-expectations-checklist.sh' "$COMMAND"
  grep -q 'check-unpushed-commits.sh' "$COMMAND"
  grep -q 'reflection-freshness.sh' "$COMMAND"
}

@test "Cancellation Mode cannot invoke archive auto-commit" {
  start="$(grep -n '^## Cancellation Mode' "$COMMAND" | cut -d: -f1)"
  end="$(grep -n '^## /dr-auto Mode' "$COMMAND" | cut -d: -f1)"
  block="$(sed -n "${start},${end}p" "$COMMAND")"
  [[ "$block" == *'MUST NOT invoke'*'archive-auto-commit.sh'* ]]
}

@test "runtime helper is registered as a dr-archive consumer" {
  # shellcheck disable=SC2016 # Backticks are literal documentation delimiters.
  grep -qF '`archive-auto-commit.sh` | `commands/dr-archive.md`' "$README"
}

@test "wiring adds no network, tag, or publication action" {
  added_contract="$(grep -n -A80 -B5 'ARCHIVE AUTO-COMMIT' "$COMMAND" || true)"
  run grep -E 'git (push|fetch|tag|remote)|gh release|npm publish' <<< "$added_contract"
  [ "$status" -eq 1 ]
}
