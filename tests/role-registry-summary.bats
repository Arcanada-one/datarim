#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CHECKER="$REPO/dev-tools/check-role-registry.sh"
    TMPROOT="$BATS_TEST_TMPDIR/role-root"
    mkdir -p "$TMPROOT/config" "$TMPROOT/skills/synthetic"
    cp "$REPO/config/role-registry.schema.json" "$TMPROOT/config/role-registry.schema.json"
    cat >"$TMPROOT/skills/synthetic/SKILL.md" <<'EOF'
---
metadata:
  context_budget_tokens: 100
---
synthetic fixture
EOF
    write_roles 1 1
}

write_roles() {
    local global="$1" max="$2" i
    {
        printf 'schema_version: 1\nglobal_max_parallel: %s\nroles:\n' "$global"
        for i in 1 2 3 4 5 6; do
            printf '  - id: synthetic-%s\n    description: synthetic\n    allowed_tools: [Read]\n    allowed_paths: ["**"]\n    forbidden_actions: []\n    max_parallel: %s\n    complexity_levels: [1]\n    default_aal: 1\n    starter_skill: skills/synthetic\n' "$i" "$max"
        done
    } >"$TMPROOT/config/roles.yaml"
}

@test "valid six-role fixture emits a measured zero-error summary" {
    run bash "$CHECKER" --summary-json --root "$TMPROOT"
    [ "$status" -eq 0 ]
    [ "$output" = '{"schema":"DatarimRoleRegistrySummary/v1","result":"VALID","exit_code":0,"diagnostic_codes":[],"validation_error_count":0,"validation_error_count_status":"MEASURED"}' ]
}

@test "cross-field errors are counted without role values" {
    write_roles 1 2
    run bash "$CHECKER" --summary-json --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *'"result":"INVALID"'* ]]
    [[ "$output" == *'"diagnostic_codes":["ROLE_REGISTRY_INVALID"]'* ]]
    [[ "$output" == *'"validation_error_count":6'* ]]
    [[ "$output" != *'synthetic-1'* ]]
}

@test "missing roles input is unavailable with null count" {
    rm "$TMPROOT/config/roles.yaml"
    run bash "$CHECKER" --summary-json --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [ "$output" = '{"schema":"DatarimRoleRegistrySummary/v1","result":"INPUT_UNAVAILABLE","exit_code":1,"diagnostic_codes":["ROLE_INPUT_UNAVAILABLE"],"validation_error_count":null,"validation_error_count_status":"NOT_MEASURED"}' ]
}

@test "tab and Unicode path arguments are accepted; control characters are refused" {
    local special="$BATS_TEST_TMPDIR/role space"$'\t'"tab-λ"
    mkdir -p "$special/config" "$special/skills/synthetic"
    cp "$TMPROOT/config/role-registry.schema.json" "$special/config/role-registry.schema.json"
    cp "$TMPROOT/skills/synthetic/SKILL.md" "$special/skills/synthetic/SKILL.md"
    cp "$TMPROOT/config/roles.yaml" "$special/config/roles.yaml"
    run bash "$CHECKER" --summary-json --root "$special"
    [ "$status" -eq 0 ]
    local control="$special"$'\n'
    run bash "$CHECKER" --summary-json --root "$control"
    [ "$status" -eq 2 ]
}
