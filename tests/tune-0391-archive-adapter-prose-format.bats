#!/usr/bin/env bats
# tune-0391-archive-adapter-prose-format.bats — qa-report-TUNE-0380 finding #1.
#
# ~40% of archive-*.md files predate the YAML-frontmatter convention (prose
# `# Archive: ID — title` heading + `**Status:**` bold-prose line, no
# frontmatter block). Before this fix, archive-adapter.sh's frontmatter-only
# parser returned an empty task_input and always derived outcome=failure for
# these files. Covers: id/title extraction from the prose heading (several
# separator punctuation variants) and outcome derivation from the bold-prose
# Status line.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ARCHIVE_ADAPTER="$REPO/plugins/dr-fleet-evolution/adapters/archive-adapter.sh"
    FIX="$REPO/tests/fixtures/fleet-evolution/archive-prose"
    TMP="$BATS_TEST_TMPDIR"
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available — adapters require jq for JSONL emission"
    fi
}

@test "P1 archive-adapter emits a non-empty task_input for a prose-header archive" {
    run "$ARCHIVE_ADAPTER" "$FIX"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -F '"task_input":"FIX-0003"'
}

@test "P2 archive-adapter derives success from a bold-prose Completed status" {
    run "$ARCHIVE_ADAPTER" "$FIX"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -F '"task_input":"FIX-0003"' | jq -e '.outcome=="success"'
}

@test "P3 archive-adapter derives failure from a non-completed bold-prose status" {
    run "$ARCHIVE_ADAPTER" "$FIX"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -F '"task_input":"FIX-0004"' | jq -e '.outcome=="failure"'
}

@test "P4 archive-adapter extracts a non-empty title for both prose separator styles" {
    run "$ARCHIVE_ADAPTER" "$FIX"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -F '"task_input":"FIX-0003"' | jq -e '.expected_output | length > 0'
    printf '%s\n' "$output" | grep -F '"task_input":"FIX-0004"' | jq -e '.expected_output | length > 0'
}

@test "P5 archive-adapter emits exactly one record per prose archive" {
    run "$ARCHIVE_ADAPTER" "$FIX"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
}
