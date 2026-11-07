#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CHECKER="$REPO/dev-tools/check-template-path-convention.sh"
    TMPROOT="$BATS_TEST_TMPDIR/template-root"
    mkdir -p "$TMPROOT/commands"
    printf 'See templates/example.md\n' >"$TMPROOT/commands/one.md"
}

@test "offence presence is true when quiet and summary are combined" {
    run bash "$CHECKER" --quiet --summary-json --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [ "$output" = '{"schema":"DatarimTemplatePathConventionSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["TEMPLATE_PATH_CONVENTION_INVALID"],"offences_present":true,"offences_present_status":"MEASURED"}' ]
}

@test "quiet mode remains silent and a clean zero-file scan is measured false" {
    run bash "$CHECKER" --quiet --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    mkdir -p "$TMPROOT/empty"
    run bash "$CHECKER" --summary-json --root "$TMPROOT/empty"
    [ "$status" -eq 0 ]
    [ "$output" = '{"schema":"DatarimTemplatePathConventionSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"offences_present":false,"offences_present_status":"MEASURED"}' ]
}

@test "missing root stays outside the JSON profile and path controls are refused" {
    run bash "$CHECKER" --summary-json --root "$TMPROOT/missing"
    [ "$status" -eq 2 ]
    [[ "$output" != *'DatarimTemplatePathConventionSummary/v1'* ]]
    local control="$TMPROOT"$'\n'
    run bash "$CHECKER" --summary-json --root "$control"
    [ "$status" -eq 2 ]
}

@test "tab and Unicode roots are accepted" {
    local special="$BATS_TEST_TMPDIR/root space"$'\t'"λ"
    mkdir -p "$special/commands"
    : >"$special/commands/one.md"
    run bash "$CHECKER" --summary-json --root "$special"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"offences_present":false'* ]]
}
