#!/usr/bin/env bats
# test_rules_loader.bats — TUNE-0165 M1.
# Verifies 3-source merge (default → user → learned) with last-write-wins on
# match-key collisions, graceful skip of missing/empty files, and shape contract.

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    TMP_RULES_DIR="$(mktemp -d)"
    export DR_ORCH_RULES_DEFAULT="$TMP_RULES_DIR/default.yaml"
    export DR_ORCH_RULES_USER="$TMP_RULES_DIR/user.yaml"
    export DR_ORCH_RULES_LEARNED="$TMP_RULES_DIR/learned.yaml"
    cat > "$DR_ORCH_RULES_DEFAULT" <<'YAML'
patterns:
  - match: "/dr-init"
    action: "/dr-init"
    confidence: 0.95
  - match: "/dr-plan"
    action: "/dr-plan"
    confidence: 0.95
YAML
}

teardown() {
    rm -rf "$TMP_RULES_DIR"
}

@test "M1: load emits JSON array of patterns from default only" {
    run bash "$DR_ORCH_DIR/scripts/rules_loader.sh" load
    [ "$status" -eq 0 ]
    n=$(echo "$output" | jq 'length')
    [ "$n" -eq 2 ]
}

@test "M1: load output entries each carry match, action, confidence" {
    run bash "$DR_ORCH_DIR/scripts/rules_loader.sh" load
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.[0] | has(\"match\") and has(\"action\") and has(\"confidence\")'"
    [ "$status" -eq 0 ]
}

@test "M1: user override wins over default for same match key" {
    cat > "$DR_ORCH_RULES_USER" <<'YAML'
patterns:
  - match: "/dr-plan"
    action: "/dr-plan"
    confidence: 0.99
YAML
    run bash "$DR_ORCH_DIR/scripts/rules_loader.sh" load
    [ "$status" -eq 0 ]
    conf=$(echo "$output" | jq '.[] | select(.match == "/dr-plan") | .confidence')
    [ "$conf" = "0.99" ]
}

@test "M1: learned override wins over user for same match key" {
    cat > "$DR_ORCH_RULES_USER" <<'YAML'
patterns:
  - match: "/dr-plan"
    action: "/dr-plan"
    confidence: 0.85
YAML
    cat > "$DR_ORCH_RULES_LEARNED" <<'YAML'
patterns:
  - match: "/dr-plan"
    action: "/dr-plan"
    confidence: 0.70
YAML
    run bash "$DR_ORCH_DIR/scripts/rules_loader.sh" load
    [ "$status" -eq 0 ]
    conf=$(echo "$output" | jq '.[] | select(.match == "/dr-plan") | .confidence')
    [ "$conf" = "0.7" ]
}

@test "M1: missing user/learned files do not fail" {
    rm -f "$DR_ORCH_RULES_USER" "$DR_ORCH_RULES_LEARNED"
    run bash "$DR_ORCH_DIR/scripts/rules_loader.sh" load
    [ "$status" -eq 0 ]
    n=$(echo "$output" | jq 'length')
    [ "$n" -eq 2 ]
}

@test "M1: empty user file is gracefully skipped" {
    : > "$DR_ORCH_RULES_USER"
    run bash "$DR_ORCH_DIR/scripts/rules_loader.sh" load
    [ "$status" -eq 0 ]
    n=$(echo "$output" | jq 'length')
    [ "$n" -eq 2 ]
}

@test "M1: missing default file yields empty array (no crash)" {
    rm -f "$DR_ORCH_RULES_DEFAULT"
    run bash "$DR_ORCH_DIR/scripts/rules_loader.sh" load
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "M1: bundled default.yaml ships at least 10 bootstrap patterns" {
    unset DR_ORCH_RULES_DEFAULT DR_ORCH_RULES_USER DR_ORCH_RULES_LEARNED
    run bash "$DR_ORCH_DIR/scripts/rules_loader.sh" load
    [ "$status" -eq 0 ]
    n=$(echo "$output" | jq 'length')
    [ "$n" -ge 10 ]
}
