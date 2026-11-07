#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CHECKER="$REPO/dev-tools/check-body-english.sh"
    TMPROOT="$BATS_TEST_TMPDIR/body-root"
    mkdir -p "$TMPROOT/commands"
    git -C "$TMPROOT" init -q
    printf 'English body\n' >"$TMPROOT/commands/clean.md"
}

@test "clean selected files report measured counts and default text remains available" {
    run bash "$CHECKER" --summary-json --root "$TMPROOT" --scope commands
    [ "$status" -eq 0 ]
    [[ "$output" == *'"checked_count":1,"checked_count_status":"MEASURED","failed_file_count":0'* ]]
    run bash "$CHECKER" --root "$TMPROOT" --scope commands
    [ "$status" -eq 0 ]
    [[ "$output" == *'RESULT: PASS'* ]]
}

@test "short allow-marker reason is a failed file without exposing its path" {
    printf 'Ж\n<!-- allow-non-ascii: tiny -->\n' >"$TMPROOT/commands/bad.md"
    run bash "$CHECKER" --summary-json --root "$TMPROOT" --scope commands
    [ "$status" -eq 1 ]
    [[ "$output" == *'"failed_file_count":1'* ]]
    [[ "$output" != *"$TMPROOT"* ]]
    [[ "$output" != *'tiny'* ]]
}

@test "an empty selection is measured zero and root control bytes are refused" {
    mkdir -p "$TMPROOT/empty"
    git -C "$TMPROOT/empty" init -q
    run bash "$CHECKER" --summary-json --root "$TMPROOT/empty" --scope commands
    [ "$status" -eq 0 ]
    [[ "$output" == *'"checked_count":0'* ]]
    local control="$TMPROOT"$'\n'
    run bash "$CHECKER" --summary-json --root "$control"
    [ "$status" -eq 2 ]
}

@test "tabbed Unicode root is accepted by the existing scope scan" {
    local special="$BATS_TEST_TMPDIR/root space"$'\t'"λ"
    mkdir -p "$special/commands"
    git -C "$special" init -q
    : >"$special/commands/clean.md"
    run bash "$CHECKER" --summary-json --root "$special" --scope commands
    [ "$status" -eq 0 ]
    [[ "$output" == *'"checked_count":1'* ]]
}
