#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CHECKER="$REPO/dev-tools/check-skill-sibling-refs.sh"
    TMPROOT="$BATS_TEST_TMPDIR/skill-root"
    mkdir -p "$TMPROOT/skills/example"
    : >"$TMPROOT/skills/example/SKILL.md"
}

@test "a clean existing skills directory reports measured zero violations" {
    run bash "$CHECKER" --summary-json "$TMPROOT"
    [ "$status" -eq 0 ]
    [ "$output" = '{"schema":"DatarimSkillSiblingReferenceSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"checked_count":1,"checked_count_status":"MEASURED","violating_skill_count":0,"violating_skill_count_status":"MEASURED"}' ]
}

@test "one skill with a self-root reference is counted once and hidden" {
    printf 'See skills/example/guide.md and skills/example/other.md\n' >"$TMPROOT/skills/example/SKILL.md"
    run bash "$CHECKER" --summary-json "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *'"violating_skill_count":1'* ]]
    [[ "$output" != *'example'* ]]
    run bash "$CHECKER" "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *'FAIL (example)'* ]]
}

@test "missing skills directory is unavailable while an empty one is measured" {
    run bash "$CHECKER" --summary-json "$BATS_TEST_TMPDIR/no-skills"
    [ "$status" -eq 2 ]
    [[ "$output" == *'"checked_count":null'* ]]
    mkdir -p "$TMPROOT/skills"
    rm -rf "$TMPROOT/skills/example"
    run bash "$CHECKER" --summary-json "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"checked_count":0'* ]]
}

@test "Unicode whitespace root is accepted and non-tab controls are refused" {
    local special="$BATS_TEST_TMPDIR/root space"$'\t'"λ"
    mkdir -p "$special/skills"
    run bash "$CHECKER" --summary-json -- "$special"
    [ "$status" -eq 0 ]
    local control="$special"$'\n'
    run bash "$CHECKER" --summary-json "$control"
    [ "$status" -eq 2 ]
}
