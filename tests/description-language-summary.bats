#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CHECKER="$REPO/dev-tools/check-frontmatter-english.sh"
    TMPROOT="$BATS_TEST_TMPDIR/description-root"
    mkdir -p "$TMPROOT/commands" "$TMPROOT/skills/sample" "$TMPROOT/agents"
    printf '%s\n' '---' 'description: English text' '---' >"$TMPROOT/commands/one.md"
    printf '%s\n' '---' 'name: sample' '---' >"$TMPROOT/skills/sample/SKILL.md"
    : >"$TMPROOT/agents/one.md"
}

@test "description scan emits measured file and finding counts" {
    run bash "$CHECKER" --summary-json "$TMPROOT"
    [ "$status" -eq 0 ]
    [ "$output" = '{"schema":"DatarimDescriptionLanguageCheckSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"checked_count":3,"checked_count_status":"MEASURED","cyrillic_description_count":0,"cyrillic_description_count_status":"MEASURED"}' ]
}

@test "Cyrillic description counts one file and hides its path and text" {
    printf '%s\n' '---' 'description: Пример' '---' >"$TMPROOT/commands/one.md"
    run bash "$CHECKER" --summary-json "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *'"cyrillic_description_count":1'* ]]
    [[ "$output" != *"$TMPROOT"* ]]
    [[ "$output" != *'Пример'* ]]
}

@test "zero matching files is a measured pass and a supported default retains text" {
    mkdir -p "$TMPROOT/empty"
    run bash "$CHECKER" --summary-json "$TMPROOT/empty"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"checked_count":0'* ]]
    run bash "$CHECKER" "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *'RESULT: PASS'* ]]
}

@test "Unicode whitespace root is accepted and non-tab controls are rejected" {
    local special="$BATS_TEST_TMPDIR/root space"$'\t'"λ"
    mkdir -p "$special/commands"
    : >"$special/commands/one.md"
    run bash "$CHECKER" --summary-json -- "$special"
    [ "$status" -eq 0 ]
    local control="$special"$'\n'
    run bash "$CHECKER" --summary-json "$control"
    [ "$status" -eq 2 ]
}
