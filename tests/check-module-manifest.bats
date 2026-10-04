#!/usr/bin/env bats
# tests/check-module-manifest.bats — module.yaml manifest validator stub.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    VALIDATOR="$REPO/dev-tools/check-module-manifest.sh"
    EXAMPLE="$REPO/templates/module.yaml"
    TMP="$BATS_TEST_TMPDIR"
}

@test "shipped example manifest is valid" {
    run bash "$VALIDATOR" "$EXAMPLE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT: VALID"* ]]
    [[ "$output" == *"skills=3"* ]]
}

@test "no argument is a usage error (exit 2)" {
    run bash "$VALIDATOR"
    [ "$status" -eq 2 ]
}

@test "missing file is a usage error (exit 2)" {
    run bash "$VALIDATOR" "$TMP/does-not-exist.yaml"
    [ "$status" -eq 2 ]
}

@test "unsupported schema_version is a hard error (exit 1)" {
    cat > "$TMP/m.yaml" <<'EOF'
schema_version: 2
module:
  id: p
  title: "t"
  version: 1.0.0
  description: "d"
skills:
  - name: a
    version: 1.0.0
    summary: "s"
EOF
    run bash "$VALIDATOR" "$TMP/m.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"schema_version"* ]]
}

@test "empty skills list is a hard error (exit 1)" {
    cat > "$TMP/m.yaml" <<'EOF'
schema_version: 1
module:
  id: p
  title: "t"
  version: 1.0.0
  description: "d"
skills:
EOF
    run bash "$VALIDATOR" "$TMP/m.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"skills list is empty"* ]]
}

@test "missing module field is a hard error (exit 1)" {
    cat > "$TMP/m.yaml" <<'EOF'
schema_version: 1
module:
  id: p
  title: "t"
skills:
  - name: a
    version: 1.0.0
    summary: "s"
EOF
    run bash "$VALIDATOR" "$TMP/m.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"module.version"* || "$output" == *"module.description"* ]]
}

@test "bad semver and non-kebab id are hard errors (exit 1)" {
    cat > "$TMP/m.yaml" <<'EOF'
schema_version: 1
module:
  id: Bad_Id
  title: "t"
  version: 1.0
  description: "d"
skills:
  - name: a
    version: 1.0.0
    summary: "s"
EOF
    run bash "$VALIDATOR" "$TMP/m.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not kebab-case"* ]]
    [[ "$output" == *"not semver"* ]]
}

@test "skill entry missing summary is a hard error (exit 1)" {
    cat > "$TMP/m.yaml" <<'EOF'
schema_version: 1
module:
  id: p
  title: "t"
  version: 1.0.0
  description: "d"
skills:
  - name: a
    version: 1.0.0
EOF
    run bash "$VALIDATOR" "$TMP/m.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing required field: summary"* ]]
}

@test "valid multi-skill manifest with requires passes (exit 0)" {
    cat > "$TMP/m.yaml" <<'EOF'
schema_version: 1
module:
  id: p
  title: "t"
  version: 2.3.4
  description: "d"
skills:
  - name: alpha
    version: 1.0.0
    summary: "first"
    stability: stable
  - name: beta
    version: 0.2.0
    summary: "second"
    stability: experimental
    requires:
      - alpha
EOF
    run bash "$VALIDATOR" "$TMP/m.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skills=2"* ]]
}
