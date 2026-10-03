#!/usr/bin/env bats
# TUNE-0268 Phase 5 — plugin operations delegate to the canonical controller.

setup() {
    CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    DATARIM_BIN="$CLI_DIR/datarim"
    TMP_DIR="$(mktemp -d)"
    export DATARIM_CLI_AUDIT_DIR="$TMP_DIR/audit"
    export DATARIM_CLI_HALT_PATH="$TMP_DIR/HALT"
    export DATARIM_CLI_AGENT_ID="$("$CLI_DIR/lib/uuid7-gen.sh")"
    unset DATARIM_CLI_NOTIFIER_TARGETS DATARIM_CLI_NOTIFY_STUB_RESULT
    CONTROLLER="$TMP_DIR/dr-plugin-controller"
    cat > "$CONTROLLER" <<'EOF'
#!/usr/bin/env bash
exit "${PLUGIN_RC:-0}"
EOF
    chmod +x "$CONTROLLER"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "plugin list delegates to the canonical dr-plugin script" {
    run bash -c 'source "$1"; _plugin_invoke() { printf "delegated:%s\n" "$*"; }; plugin_subcommand list' _ "$CLI_DIR/subcommands/plugin.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "delegated:list" ]
    grep -q 'scripts/dr-plugin.sh' "$CLI_DIR/subcommands/plugin.sh"
    ! grep -q 'run_subcommand' "$CLI_DIR/subcommands/plugin.sh"
}

@test "plugin wrapper preserves canonical controller exit codes" {
    for expected in 0 1 2 3 64; do
        run bash -c 'source "$1"; DR_PLUGIN_SCRIPT="$2"; export PLUGIN_RC="$3"; plugin_subcommand list' _ \
            "$CLI_DIR/subcommands/plugin.sh" "$CONTROLLER" "$expected"
        [ "$status" -eq "$expected" ]
    done
}

@test "plugin enable passes an absolute source path unchanged" {
    run bash -c 'source "$1"; _plugin_invoke() { printf "delegated:%s\n" "$*"; }; plugin_subcommand enable /opt/plugins/example' _ "$CLI_DIR/subcommands/plugin.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "delegated:enable /opt/plugins/example" ]
}

@test "plugin disable reaches canonical delegation" {
    run bash -c 'source "$1"; _plugin_invoke() { printf "delegated:%s\n" "$*"; }; plugin_subcommand disable dr-orchestrate' _ "$CLI_DIR/subcommands/plugin.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "delegated:disable dr-orchestrate" ]
}

@test "plugin sync and doctor --fix remain in parity with the canonical CLI" {
    run bash -c 'source "$1"; _plugin_invoke() { printf "delegated:%s\n" "$*"; }; plugin_subcommand sync' _ "$CLI_DIR/subcommands/plugin.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "delegated:sync" ]
    run bash -c 'source "$1"; _plugin_invoke() { printf "delegated:%s\n" "$*"; }; plugin_subcommand doctor --fix' _ "$CLI_DIR/subcommands/plugin.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "delegated:doctor --fix" ]
}

@test "HALT is evaluated before Phase 5 plugin dispatch" {
    : > "$DATARIM_CLI_HALT_PATH"
    run "$DATARIM_BIN" plugin list
    [ "$status" -eq 17 ]
    [[ "$output" == *"HALT"* ]]
}
