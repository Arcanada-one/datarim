#!/usr/bin/env bats
# tests/test-fleet-evolution-adapters.bats — archive + dr-dream source adapters.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ARCHIVE_ADAPTER="$REPO/plugins/dr-fleet-evolution/adapters/archive-adapter.sh"
    DRDREAM_ADAPTER="$REPO/plugins/dr-fleet-evolution/adapters/dr-dream-adapter.sh"
    FIX="$REPO/tests/fixtures/fleet-evolution"
    TMP="$BATS_TEST_TMPDIR"
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available — adapters require jq for JSONL emission"
    fi
}

@test "archive-adapter is executable" {
    [ -x "$ARCHIVE_ADAPTER" ]
}

@test "dr-dream-adapter is executable" {
    [ -x "$DRDREAM_ADAPTER" ]
}

@test "archive-adapter emits valid JSONL for fixtures" {
    run "$ARCHIVE_ADAPTER" "$FIX/archive"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
    # every line is a valid JSON object with the contract fields
    printf '%s\n' "$output" | while IFS= read -r l; do
        printf '%s' "$l" | jq -e 'has("task_input") and has("outcome") and .source=="archive"'
    done
}

@test "archive-adapter derives success for a clean completion" {
    run "$ARCHIVE_ADAPTER" "$FIX/archive"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -F '"task_input":"FIX-0001"' | jq -e '.outcome=="success"'
}

@test "archive-adapter derives failure when regressions slipped past verify" {
    run "$ARCHIVE_ADAPTER" "$FIX/archive"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -F '"task_input":"FIX-0002"' | jq -e '.outcome=="failure"'
}

@test "archive-adapter exits 0 with empty output on a directory with no archives" {
    mkdir -p "$TMP/empty"
    run "$ARCHIVE_ADAPTER" "$TMP/empty"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "archive-adapter exits 2 on usage error (no arg)" {
    run "$ARCHIVE_ADAPTER"
    [ "$status" -eq 2 ]
}

@test "archive-adapter exits 1 on a missing directory" {
    run "$ARCHIVE_ADAPTER" "$TMP/does-not-exist"
    [ "$status" -eq 1 ]
}

@test "dr-dream-adapter emits one record per gap signal" {
    run "$DRDREAM_ADAPTER" "$FIX/dr-dream"
    [ "$status" -eq 0 ]
    # fixture has 3 gap/improvement bullets
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 3 ]
    printf '%s\n' "$output" | while IFS= read -r l; do
        printf '%s' "$l" | jq -e '.source=="dr-dream" and .outcome=="failure"'
    done
}

@test "dr-dream-adapter exits 0 with empty output when no gaps" {
    mkdir -p "$TMP/nodreams"
    printf -- '---\nid: X\n---\n\n## Health metrics\nAll green.\n' > "$TMP/nodreams/reflection-X.md"
    run "$DRDREAM_ADAPTER" "$TMP/nodreams"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "dr-dream-adapter exits 2 on usage error (no arg)" {
    run "$DRDREAM_ADAPTER"
    [ "$status" -eq 2 ]
}
