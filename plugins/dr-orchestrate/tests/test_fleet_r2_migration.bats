#!/usr/bin/env bats
# test_fleet_r2_migration.bats — V-AC-10. The fleet interactive path is ADDITIVE;
# the existing headless inference resolve() path (cmd_run.sh consumer) is intact.

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    RESOLVER="$PLUGIN_ROOT/scripts/subagent_resolver.sh"
    TMP_BIN="$(mktemp -d)"
    export STATE_DIR="$(mktemp -d)"
    export PATH="$TMP_BIN:$PATH"
    export DR_ORCH_RESOLVER_TIMEOUT_S=3
}

teardown() { rm -rf "$TMP_BIN" "$STATE_DIR"; }

@test "V-AC-10: inference resolve() still returns the documented JSON shape" {
    cat > "$TMP_BIN/dr-orch-mock-x" <<'EOF'
#!/usr/bin/env bash
printf '%s' '{"action":"/dr-plan","confidence":0.9,"reason":"ok"}'
EOF
    chmod +x "$TMP_BIN/dr-orch-mock-x"
    run env DR_ORCH_SUBAGENT_CHAIN="mock-x" bash "$RESOLVER" resolve "some pane text"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.action and (.confidence|type=="number") and .backend_used' >/dev/null
}

@test "V-AC-10: inference backend mapping for claude KEEPS --print (headless inference unchanged)" {
    # The inference path (distinct from fleet) intentionally retains --print.
    run bash "$RESOLVER" _resolve_backend claude
    [ "$status" -eq 0 ]
    echo "$output" | grep -q -- "--print"
}

@test "V-AC-10: fleet and inference paths are SEPARATE functions (no cross-contamination)" {
    # fleet claude form has no --print; inference claude form has --print.
    fleet="$(bash "$RESOLVER" _resolve_fleet_backend claude)"
    infer="$(bash "$RESOLVER" _resolve_backend claude)"
    ! echo "$fleet" | grep -q -- "--print"
    echo "$infer" | grep -q -- "--print"
}
