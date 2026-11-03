#!/usr/bin/env bats

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    CHECKER="$REPO/dev-tools/check-module-manifest.sh"
    TMPROOT="$BATS_TEST_TMPDIR/module-pack"
    mkdir -p "$TMPROOT/skills/alpha"
    : >"$TMPROOT/skills/alpha/SKILL.md"
    cat >"$TMPROOT/module.yaml" <<'EOF'
schema_version: 1
module:
  id: synthetic-pack
  title: Synthetic
  version: 1.0.0
  description: Synthetic fixture
skills:
  - name: alpha
    version: 1.0.0
    summary: Synthetic skill
EOF
}

@test "valid manifest emits the existing eight-field contract" {
    run bash "$CHECKER" --summary-json "$TMPROOT/module.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = '{"schema":"DatarimModuleManifestSummary/v1","result":"VALID","exit_code":0,"diagnostic_codes":[],"skill_count":1,"skill_count_status":"MEASURED","warning_count":0,"warning_count_status":"MEASURED"}' ]
}

@test "warning-only result remains valid and warnings are counted" {
    rm "$TMPROOT/skills/alpha/SKILL.md"
    run bash "$CHECKER" --summary-json "$TMPROOT/module.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"result":"VALID"'* ]]
    [[ "$output" == *'"warning_count":1'* ]]
    [[ "$output" != *'synthetic-pack'* ]]
}

@test "structural failure records measured count and missing input is unavailable" {
    sed -i 's/version: 1.0.0/version: 1.0/' "$TMPROOT/module.yaml"
    run bash "$CHECKER" --summary-json "$TMPROOT/module.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *'"result":"INVALID"'* ]]
    [[ "$output" == *'"skill_count_status":"MEASURED"'* ]]
    run bash "$CHECKER" --summary-json "$TMPROOT/absent.yaml"
    [ "$status" -eq 2 ]
    [[ "$output" == *'"result":"INPUT_UNAVAILABLE"'* ]]
    [[ "$output" == *'"skill_count":null'* ]]
}

@test "space, tab, and Unicode manifest paths work; non-tab controls are refused" {
    local special="$BATS_TEST_TMPDIR/pack space"$'\t'"λ"
    mkdir -p "$special/skills/alpha"
    cp "$TMPROOT/skills/alpha/SKILL.md" "$special/skills/alpha/SKILL.md"
    cp "$TMPROOT/module.yaml" "$special/module.yaml"
    run bash "$CHECKER" --summary-json "$special/module.yaml"
    [ "$status" -eq 0 ]
    local control="$special/module.yaml"$'\n'
    run bash "$CHECKER" --summary-json "$control"
    [ "$status" -eq 2 ]
}
