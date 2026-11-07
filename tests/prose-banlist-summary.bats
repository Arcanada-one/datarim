#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CHECKER="$REPO/dev-tools/check-banlist-on-prose.sh"
    TMPROOT="$BATS_TEST_TMPDIR/banlist"
    mkdir -p "$TMPROOT"
    printf 'blockedword\n' >"$TMPROOT/ban.txt"
    printf 'allowedword\n' >"$TMPROOT/white.txt"
    printf 'ordinary clean prose\n' >"$TMPROOT/input.md"
}

@test "clean Russian scan reports measured zero offences" {
    run bash "$CHECKER" --summary-json --file "$TMPROOT/input.md" --banlist "$TMPROOT/ban.txt" --whitelist "$TMPROOT/white.txt" --language ru
    [ "$status" -eq 0 ]
    [ "$output" = '{"schema":"DatarimProseBanlistSummary/v1","result":"CLEAN","exit_code":0,"diagnostic_codes":[],"offence_count":0,"offence_count_status":"MEASURED"}' ]
}

@test "one token match is counted without emitting token or path" {
    printf 'blockedword\n' >"$TMPROOT/input.md"
    run bash "$CHECKER" --summary-json --file "$TMPROOT/input.md" --banlist "$TMPROOT/ban.txt" --whitelist "$TMPROOT/white.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *'"offence_count":1'* ]]
    [[ "$output" != *'blockedword'* ]]
    [[ "$output" != *"$TMPROOT"* ]]
}

@test "non-Russian language is not applicable and missing list is unavailable" {
    run bash "$CHECKER" --summary-json --file "$TMPROOT/input.md" --language en
    [ "$status" -eq 0 ]
    [[ "$output" == *'"result":"NOT_APPLICABLE"'* ]]
    [[ "$output" == *'"offence_count":null'* ]]
    run bash "$CHECKER" --summary-json --file "$TMPROOT/input.md" --banlist "$TMPROOT/missing.txt" --whitelist "$TMPROOT/white.txt" --language ru
    [ "$status" -eq 1 ]
    [[ "$output" == *'PROSE_BANLIST_UNAVAILABLE'* ]]
}

@test "tab and Unicode list paths work and control bytes are refused" {
    local special="$BATS_TEST_TMPDIR/lists space"$'\t'"λ"
    mkdir -p "$special"
    printf 'blockedword\n' >"$special/ban.txt"
    printf 'allowedword\n' >"$special/white.txt"
    run bash "$CHECKER" --summary-json --file "$TMPROOT/input.md" --banlist "$special/ban.txt" --whitelist "$special/white.txt"
    [ "$status" -eq 0 ]
    local control="$special/ban.txt"$'\n'
    run bash "$CHECKER" --summary-json --file "$TMPROOT/input.md" --banlist "$control" --whitelist "$special/white.txt"
    [ "$status" -eq 2 ]
}
