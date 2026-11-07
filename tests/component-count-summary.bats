#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CHECKER="$REPO/dev-tools/check-component-counts.sh"
    TMPROOT="$BATS_TEST_TMPDIR/component-root"
    mkdir -p "$TMPROOT/commands" "$TMPROOT/agents" "$TMPROOT/skills/example" "$TMPROOT/templates"
    : >"$TMPROOT/commands/one.md"
    : >"$TMPROOT/skills/example/SKILL.md"
    : >"$TMPROOT/templates/one.md"
    printf '1 commands\n0 agents\n1 skills\n1 templates\n' >"$TMPROOT/AGENTS.md"
    : >"$TMPROOT/README.md"
}

@test "matching declarations produce a measured clean summary" {
    run bash "$CHECKER" --summary-json --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [ "$output" = '{"schema":"DatarimComponentCountSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"drift_count":0,"drift_count_status":"MEASURED"}' ]
}

@test "drift count is the number of mismatched claims and report mode remains separate" {
    printf '2 commands\n0 agents\n1 skills\n1 templates\n' >"$TMPROOT/AGENTS.md"
    run bash "$CHECKER" --summary-json --report --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [ "$output" = '{"schema":"DatarimComponentCountSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["COMPONENT_COUNT_DRIFT"],"drift_count":1,"drift_count_status":"MEASURED"}' ]
    run bash "$CHECKER" --report --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *'claims 2'* ]]
}

@test "missing instruction root is unavailable rather than a measured zero" {
    mkdir -p "$TMPROOT/missing"
    run bash "$CHECKER" --summary-json --root "$TMPROOT/missing"
    [ "$status" -eq 3 ]
    [ "$output" = '{"schema":"DatarimComponentCountSummary/v1","result":"INPUT_UNAVAILABLE","exit_code":3,"diagnostic_codes":["COMPONENT_ROOT_UNAVAILABLE"],"drift_count":null,"drift_count_status":"NOT_MEASURED"}' ]
}

@test "tab and Unicode roots are accepted and non-tab controls are refused" {
    local special="$BATS_TEST_TMPDIR/root space	tab-λ"
    mkdir -p "$special"
    : >"$special/AGENTS.md"
    run bash "$CHECKER" --summary-json --root "$special"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"drift_count":0'* ]]
    local control="$special"$'\n'
    run bash "$CHECKER" --summary-json --root "$control"
    [ "$status" -eq 2 ]
}
