#!/usr/bin/env bats

SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/check-skill-frontmatter.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/skills/example"
    : >"$TMPROOT/AGENTS.md"
}

teardown() {
    rm -rf "$TMPROOT"
}

write_skill() {
    local path="$1"
    shift
    cat >"$path" <<EOF
$@
EOF
}

@test "summary reports fixed PASS shape and measured count" {
    write_skill "$TMPROOT/skills/example/SKILL.md" "---
name: example
description: valid synthetic skill
---"

    run "$SCRIPT" --summary-json --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [ "$output" = '{"schema":"DatarimSkillFrontmatterValidationSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"checked_count":1,"checked_count_status":"MEASURED","warning_count":0,"warning_count_status":"MEASURED"}' ]
}

@test "tabbed synthetic roots and skill paths preserve counts, exits, privacy, and inputs" {
    local tab=$'\t'
    local special_root="$TMPROOT/root with whitespace${tab}tab"
    local skill_name="name with whitespace${tab}tab"
    local skill_path="$special_root/skills/$skill_name/SKILL.md"
    local secret_value='synthetic-secret-value-DO-NOT-EMIT'
    mkdir -p "$special_root/skills/$skill_name"
    : >"$special_root/AGENTS.md"
    write_skill "$skill_path" "---
name: synthetic
description: tabbed synthetic path
model: $secret_value
---"

    local before after default_status
    before="$(sha256sum <"$skill_path" | cut -d' ' -f1)"
    run "$SCRIPT" --root "$special_root"
    default_status="$status"
    [ "$default_status" -eq 1 ]

    run "$SCRIPT" --summary-json --root "$special_root"
    [ "$status" -eq "$default_status" ]
    [ "$output" = '{"schema":"DatarimSkillFrontmatterValidationSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["SKILL_FRONTMATTER_INVALID"],"checked_count":1,"checked_count_status":"MEASURED","warning_count":0,"warning_count_status":"MEASURED"}' ]
    [[ "$output" != *"$special_root"* ]]
    [[ "$output" != *"$skill_name"* ]]
    [[ "$output" != *"$secret_value"* ]]
    after="$(sha256sum <"$skill_path" | cut -d' ' -f1)"
    [ "$before" = "$after" ]
    printf '# synthetic_fixture_sha256_before=%s after=%s\n' "$before" "$after"
}

@test "summary reports invalid structure without leaking a synthetic name or value" {
    local secret_name='synthetic-skill-path-DO-NOT-EMIT'
    local secret_value='frontmatter-secret-value-DO-NOT-EMIT'
    mkdir -p "$TMPROOT/skills/$secret_name"
    write_skill "$TMPROOT/skills/$secret_name/SKILL.md" "---
name: example
description: invalid synthetic skill
model: $secret_value
---"

    run "$SCRIPT" --root "$TMPROOT" --summary-json
    [ "$status" -eq 1 ]
    [ "$output" = '{"schema":"DatarimSkillFrontmatterValidationSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["SKILL_FRONTMATTER_INVALID"],"checked_count":1,"checked_count_status":"MEASURED","warning_count":0,"warning_count_status":"MEASURED"}' ]
    [[ "$output" != *"$secret_name"* ]]
    [[ "$output" != *"$secret_value"* ]]
    [[ "$output" != *"$TMPROOT"* ]]
}

@test "warning-only legacy runtime remains PASS with a measured warning" {
    write_skill "$TMPROOT/skills/example/SKILL.md" "---
name: example
description: warning only
runtime: [synthetic]
---"

    run "$SCRIPT" --summary-json --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [ "$output" = '{"schema":"DatarimSkillFrontmatterValidationSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"checked_count":1,"checked_count_status":"MEASURED","warning_count":1,"warning_count_status":"MEASURED"}' ]
}

@test "empty scan reports measured zero counts" {
    run "$SCRIPT" --summary-json --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [ "$output" = '{"schema":"DatarimSkillFrontmatterValidationSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"checked_count":0,"checked_count_status":"MEASURED","warning_count":0,"warning_count_status":"MEASURED"}' ]
}

@test "summary and default invocation preserve the same decision" {
    write_skill "$TMPROOT/skills/example/SKILL.md" "---
name: example
description: valid synthetic skill
---"

    run "$SCRIPT" --root "$TMPROOT"
    local default_status="$status"
    local default_output="$output"
    run "$SCRIPT" --summary-json --root "$TMPROOT"
    [ "$status" -eq "$default_status" ]
    [[ "$default_output" == *"RESULT: PASS"* ]]
    [[ "$output" == *'"result":"PASS"'* ]]
}

@test "default invocation keeps its existing summary text" {
    write_skill "$TMPROOT/skills/example/SKILL.md" "---
name: example
description: valid synthetic skill
---"

    run "$SCRIPT" --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [ "$output" = $'\n=== Summary ===\nchecked=1 frontmatter blocks, warnings=0\nRESULT: PASS (V-AC-4 + AC-7)' ]
}

@test "summary scan leaves its synthetic input unchanged" {
    write_skill "$TMPROOT/skills/example/SKILL.md" "---
name: example
description: immutable synthetic input
---"
    local before after
    before="$(sha256sum "$TMPROOT/skills/example/SKILL.md")"
    run "$SCRIPT" --summary-json --root "$TMPROOT"
    [ "$status" -eq 0 ]
    after="$(sha256sum "$TMPROOT/skills/example/SKILL.md")"
    [ "$before" = "$after" ]
}

@test "summary keeps the existing flat and nested scan while excluding reserved namespace" {
    write_skill "$TMPROOT/skills/example/SKILL.md" "---
name: nested
description: nested synthetic skill
---"
    write_skill "$TMPROOT/skills/flat.md" "---
name: flat
description: flat synthetic skill
---"
    mkdir -p "$TMPROOT/skills/.system/private"
    write_skill "$TMPROOT/skills/.system/private/SKILL.md" "---
not_validated: true
---"

    run "$SCRIPT" --summary-json --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"checked_count":2'* ]]
}

@test "handled instruction guard failure emits only the fixed summary" {
    : >"$TMPROOT/CLAUDE.md"

    run "$SCRIPT" --summary-json --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [ "$output" = '{"schema":"DatarimSkillFrontmatterValidationSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["SKILL_FRONTMATTER_INVALID"],"checked_count":0,"checked_count_status":"MEASURED","warning_count":0,"warning_count_status":"MEASURED"}' ]
    [[ "$output" != *"CLAUDE"* ]]
    [[ "$output" != *"$TMPROOT"* ]]
}
