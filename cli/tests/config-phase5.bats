#!/usr/bin/env bats
# TUNE-0268 Phase 5 — non-secret derived reads and fail-closed writes.

setup() {
    CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    DATARIM_BIN="$CLI_DIR/datarim"
    TMP_DIR="$(mktemp -d)"
    export HOME="$TMP_DIR/home"
    export DATARIM_WORKSPACE_ROOT="$TMP_DIR/workspace"
    export DATARIM_CLI_AUDIT_DIR="$TMP_DIR/audit"
    export DATARIM_CLI_HALT_PATH="$TMP_DIR/HALT"
    mkdir -p "$HOME/.config/datarim-cli" "$DATARIM_WORKSPACE_ROOT/datarim"
    export DATARIM_ROOT="$DATARIM_WORKSPACE_ROOT"
    printf '9.9.9-test\n' > "$DATARIM_ROOT/VERSION"
    printf '%s\n' 'notifier_targets: secret-bearing' > "$HOME/.config/datarim-cli/config.yaml"
    printf '%s\n' '# Enabled Plugins' 'secret_ref: must-not-leak' > "$DATARIM_WORKSPACE_ROOT/datarim/enabled-plugins.md"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "Phase 5 config get exposes only derived framework version" {
    run "$DATARIM_BIN" config get framework_version
    [ "$status" -eq 0 ]
    [ "$output" = "9.9.9-test" ]
}

@test "Phase 5 config get --json emits the canonical envelope" {
    run "$DATARIM_BIN" config get plugin_manifest_status --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e '.command == "config get" and .data.key == "plugin_manifest_status" and .data.value == "present"' >/dev/null
}

@test "Phase 5 config get rejects arbitrary keys without returning source bytes" {
    run "$DATARIM_BIN" config get notifier_targets
    [ "$status" -eq 20 ]
    [[ "$output" != *"secret-bearing"* ]]
}

@test "current-ground config set is read-only and preserves both sources" {
    user_before="$(sha256sum "$HOME/.config/datarim-cli/config.yaml" | awk '{print $1}')"
    manifest_before="$(sha256sum "$DATARIM_WORKSPACE_ROOT/datarim/enabled-plugins.md" | awk '{print $1}')"
    run "$DATARIM_BIN" config set debug false
    [ "$status" -eq 20 ]
    [ "$user_before" = "$(sha256sum "$HOME/.config/datarim-cli/config.yaml" | awk '{print $1}')" ]
    [ "$manifest_before" = "$(sha256sum "$DATARIM_WORKSPACE_ROOT/datarim/enabled-plugins.md" | awk '{print $1}')" ]
}

@test "V-AC-11: aal_class downgrade fails closed with exit 20 and preserves files" {
    before="$(sha256sum "$DATARIM_WORKSPACE_ROOT/datarim/enabled-plugins.md" | awk '{print $1}')"
    run "$DATARIM_BIN" config set aal_class 2
    [ "$status" -eq 20 ]
    [[ "$output" == *"AAL_LOCKED_KEY"* ]]
    after="$(sha256sum "$DATARIM_WORKSPACE_ROOT/datarim/enabled-plugins.md" | awk '{print $1}')"
    [ "$before" = "$after" ]
}

@test "enabled_plugins cannot create split-brain with the plugin manifest" {
    run "$DATARIM_BIN" config set enabled_plugins anything
    [ "$status" -eq 20 ]
    ! grep -q 'anything' "$DATARIM_WORKSPACE_ROOT/datarim/enabled-plugins.md"
}

@test "config set refuses unsafe or unknown key syntax" {
    run "$DATARIM_BIN" config set 'x.y' bad
    [ "$status" -eq 2 ]
    run "$DATARIM_BIN" config set unknown_key bad
    [ "$status" -eq 20 ]
}

@test "HALT is evaluated before Phase 5 config dispatch" {
    : > "$DATARIM_CLI_HALT_PATH"
    run "$DATARIM_BIN" config get framework_version
    [ "$status" -eq 17 ]
    [[ "$output" == *"HALT"* ]]
}
