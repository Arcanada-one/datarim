#!/usr/bin/env bats
# test_subagent_resolver.bats — TUNE-0165 M2.
# Verifies multi-backend dispatch, lenient JSON parse, fallback chain, timeout,
# FD-3 close, and shape contract for confidence/backend_used.

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    TMP_BIN="$(mktemp -d)"
    TMP_STATE="$(mktemp -d)"
    export STATE_DIR="$TMP_STATE"
    export DR_ORCH_RESOLVER_TIMEOUT_S=3
    export PATH="$TMP_BIN:$PATH"
    # default chain isolates to mocks
    export DR_ORCH_SUBAGENT_CHAIN="mock-primary mock-secondary mock-tertiary"
}

teardown() {
    rm -rf "$TMP_BIN" "$TMP_STATE"
}

_make_mock() {
    local name="$1"; local payload="$2"
    cat > "$TMP_BIN/dr-orch-mock-${name}" <<EOF
#!/usr/bin/env bash
printf '%s' '${payload//\'/\'\\\'\'}'
EOF
    chmod +x "$TMP_BIN/dr-orch-mock-${name}"
}

@test "M2: high-confidence response returns parsed JSON with backend_used" {
    _make_mock primary '{"action":"/dr-plan","confidence":0.95,"reason":"exact"}'
    run bash "$DR_ORCH_DIR/scripts/subagent_resolver.sh" resolve "some pane text"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r .action)" = "/dr-plan" ]
    [ "$(echo "$output" | jq -r .backend_used)" = "mock-primary" ]
    conf="$(echo "$output" | jq -r .confidence)"
    [ "$conf" = "0.95" ]
}

@test "M2: low-confidence response is propagated verbatim (consumer gates)" {
    _make_mock primary '{"action":"/dr-init","confidence":0.20,"reason":"weak"}'
    run bash "$DR_ORCH_DIR/scripts/subagent_resolver.sh" resolve "ambiguous text"
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.confidence == 0.20'"
    [ "$status" -eq 0 ]
}

@test "M2: threshold boundary 0.80 propagates (no gate inside resolver)" {
    _make_mock primary '{"action":"/dr-do","confidence":0.80,"reason":"boundary"}'
    run bash "$DR_ORCH_DIR/scripts/subagent_resolver.sh" resolve "pane"
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.confidence == 0.80'"
    [ "$status" -eq 0 ]
}

@test "M2: threshold boundary 0.79 propagates (consumer escalates)" {
    _make_mock primary '{"action":"/dr-do","confidence":0.79,"reason":"below"}'
    run bash "$DR_ORCH_DIR/scripts/subagent_resolver.sh" resolve "pane"
    [ "$status" -eq 0 ]
    run bash -c "echo '$output' | jq -e '.confidence == 0.79'"
    [ "$status" -eq 0 ]
}

@test "M2: malformed primary triggers fallback to secondary" {
    _make_mock primary 'not a json blob at all just prose'
    _make_mock secondary '{"action":"/dr-qa","confidence":0.88,"reason":"recovered"}'
    run bash "$DR_ORCH_DIR/scripts/subagent_resolver.sh" resolve "pane"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r .backend_used)" = "mock-secondary" ]
    [ "$(echo "$output" | jq -r .action)" = "/dr-qa" ]
}

@test "M2: missing backend (command not in PATH) is skipped silently" {
    # only secondary present
    _make_mock secondary '{"action":"/dr-archive","confidence":0.92,"reason":"only-survivor"}'
    run bash -c "bash '$DR_ORCH_DIR/scripts/subagent_resolver.sh' resolve 'pane' 2>/dev/null"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r .backend_used)" = "mock-secondary" ]
}

@test "M2: all backends absent yields chain_exhausted with confidence 0" {
    run bash -c "bash '$DR_ORCH_DIR/scripts/subagent_resolver.sh' resolve 'pane' 2>/dev/null"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r .reason)" = "chain_exhausted" ]
    [ "$(echo "$output" | jq -r .confidence)" = "0" ]
    [ "$(echo "$output" | jq -r .backend_used)" = "none" ]
}

@test "M2: lenient parser extracts first JSON block from prose wrapper" {
    _make_mock primary 'Here is the answer: {"action":"/dr-prd","confidence":0.87,"reason":"prose-wrapped"} and trailing junk.'
    run bash "$DR_ORCH_DIR/scripts/subagent_resolver.sh" resolve "pane"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r .action)" = "/dr-prd" ]
}

@test "M2: timeout falls through to next backend" {
    # primary sleeps longer than DR_ORCH_RESOLVER_TIMEOUT_S=3
    cat > "$TMP_BIN/dr-orch-mock-primary" <<'EOF'
#!/usr/bin/env bash
sleep 10
echo '{"action":"/dr-do","confidence":0.99}'
EOF
    chmod +x "$TMP_BIN/dr-orch-mock-primary"
    _make_mock secondary '{"action":"/dr-archive","confidence":0.91,"reason":"after-timeout"}'
    run bash "$DR_ORCH_DIR/scripts/subagent_resolver.sh" resolve "pane"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r .backend_used)" = "mock-secondary" ]
}

@test "M2: missing-backend warning is deduped via state-dir sentinel" {
    _make_mock secondary '{"action":"/dr-do","confidence":0.95}'
    # first invocation: primary missing → sentinel created
    run bash "$DR_ORCH_DIR/scripts/subagent_resolver.sh" resolve "first"
    [ "$status" -eq 0 ]
    [ -f "$STATE_DIR/.warned.mock-primary" ]
    # second invocation: should not WARN again
    run bash "$DR_ORCH_DIR/scripts/subagent_resolver.sh" resolve "second"
    [ "$status" -eq 0 ]
}
