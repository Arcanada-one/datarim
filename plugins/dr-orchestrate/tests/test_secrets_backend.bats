#!/usr/bin/env bats
# test_secrets_backend.bats — V-AC 9

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    export TMP_SECRETS_DIR="$(mktemp -d)"
    SECRETS_FILE="$TMP_SECRETS_DIR/secrets.yaml"
    printf 'test_key: test_value\nquoted: "spaced value"\n' > "$SECRETS_FILE"
    chmod 600 "$SECRETS_FILE"
}

teardown() {
    rm -rf "$TMP_SECRETS_DIR"
}

@test "V-AC-9: yaml_get reads value at mode 0600" {
    run bash "$DR_ORCH_DIR/scripts/secrets_backend.sh" yaml_get "$SECRETS_FILE" test_key
    [ "$status" -eq 0 ]
    [ "$output" = "test_value" ]
}

@test "V-AC-9: yaml_get strips surrounding quotes" {
    run bash "$DR_ORCH_DIR/scripts/secrets_backend.sh" yaml_get "$SECRETS_FILE" quoted
    [ "$status" -eq 0 ]
    [ "$output" = "spaced value" ]
}

@test "V-AC-9: yaml_get rejects mode != 0600" {
    chmod 644 "$SECRETS_FILE"
    run bash "$DR_ORCH_DIR/scripts/secrets_backend.sh" yaml_get "$SECRETS_FILE" test_key
    [ "$status" -eq 2 ]
}

@test "V-AC-9: yaml_get reports missing file" {
    run bash "$DR_ORCH_DIR/scripts/secrets_backend.sh" yaml_get "$TMP_SECRETS_DIR/missing.yaml" test_key
    [ "$status" -eq 1 ]
}

@test "V-AC-9: vault_get is a Phase-2 stub" {
    run bash "$DR_ORCH_DIR/scripts/secrets_backend.sh" vault_get any
    [ "$status" -eq 99 ]
}
