#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
#
# Tests for install.sh --profile orchestrator (TUNE-0169).
#
# Contract under test (PRD-TUNE-0104 § Public/Personal Split):
#   - --profile orchestrator is a standalone action (does not touch
#     $CLAUDE_DIR, does not require --with-claude/--with-codex/--project).
#   - Prompts for secrets backend (yaml|vault), audit sink (jsonl|opsbot),
#     telegram bridge endpoint (optional free-text URL).
#   - Writes $DATARIM_ORCH_CONFIG_DIR/local.yaml (default
#     ~/.config/datarim-orchestrate/local.yaml) at mode 0600.
#   - The three fields round-trip correctly.
#   - Idempotent: re-run without --force preserves existing values;
#     --force reconfigures/overwrites.
#   - Non-TTY with no env pre-answer and no piped input falls back to sane
#     defaults (yaml / jsonl / blank) instead of hanging.
#
# Isolation: HOME is redirected to a per-test tmpdir (FAKE_HOME) so the config
# dir never touches the operator's real ~/.config.

load 'helpers/install_fixture'

setup() {
    setup_fixture
}

# run_orchestrator_profile [extra install.sh args...]
# Uses FAKE_REPO's install.sh (with the isolation the fixture already buys)
# and redirects both HOME (config dir base) and DATARIM_ORCH_CONFIG_DIR
# explicitly so assertions do not depend on the $HOME/.config derivation.
run_orchestrator_profile() {
    export ORCH_CONFIG_DIR="$BATS_TEST_TMPDIR/orch-config"
    run env HOME="$FAKE_HOME" DATARIM_ORCH_CONFIG_DIR="$ORCH_CONFIG_DIR" \
        "$FAKE_REPO/install.sh" --profile orchestrator "$@"
}

@test "OP1 --profile orchestrator with env pre-answers creates local.yaml" {
    run env HOME="$FAKE_HOME" DATARIM_ORCH_CONFIG_DIR="$BATS_TEST_TMPDIR/orch-config" \
        DATARIM_ORCH_SECRETS_BACKEND=vault DATARIM_ORCH_AUDIT_SINK=opsbot \
        DATARIM_ORCH_TELEGRAM_ENDPOINT="https://bridge.example/hook" \
        "$FAKE_REPO/install.sh" --profile orchestrator
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/orch-config/local.yaml" ]
    # Does NOT touch $CLAUDE_DIR — standalone action.
    [ ! -e "$FAKE_CLAUDE/agents" ]
}

@test "OP2 local.yaml file mode is 0600" {
    run env HOME="$FAKE_HOME" DATARIM_ORCH_CONFIG_DIR="$BATS_TEST_TMPDIR/orch-config" \
        DATARIM_ORCH_SECRETS_BACKEND=yaml DATARIM_ORCH_AUDIT_SINK=jsonl \
        DATARIM_ORCH_TELEGRAM_ENDPOINT="" \
        "$FAKE_REPO/install.sh" --profile orchestrator
    [ "$status" -eq 0 ]
    mode="$(stat -c %a "$BATS_TEST_TMPDIR/orch-config/local.yaml" 2>/dev/null \
        || stat -f %Lp "$BATS_TEST_TMPDIR/orch-config/local.yaml")"
    [ "$mode" = "600" ]
}

@test "OP3 the three fields round-trip correctly (env pre-answer path)" {
    run env HOME="$FAKE_HOME" DATARIM_ORCH_CONFIG_DIR="$BATS_TEST_TMPDIR/orch-config" \
        DATARIM_ORCH_SECRETS_BACKEND=vault DATARIM_ORCH_AUDIT_SINK=opsbot \
        DATARIM_ORCH_TELEGRAM_ENDPOINT="https://bridge.example/hook" \
        "$FAKE_REPO/install.sh" --profile orchestrator
    [ "$status" -eq 0 ]
    grep -qx "secrets_backend: vault" "$BATS_TEST_TMPDIR/orch-config/local.yaml"
    grep -qx "audit_sink: opsbot" "$BATS_TEST_TMPDIR/orch-config/local.yaml"
    grep -qx 'telegram_bridge_endpoint: "https://bridge.example/hook"' "$BATS_TEST_TMPDIR/orch-config/local.yaml"
}

@test "OP4 the three fields round-trip correctly (piped/heredoc stdin path)" {
    run bash -c "printf 'vault\njsonl\nhttps://bridge.example/foo\n' | env HOME='$FAKE_HOME' DATARIM_ORCH_CONFIG_DIR='$BATS_TEST_TMPDIR/orch-config' '$FAKE_REPO/install.sh' --profile orchestrator"
    [ "$status" -eq 0 ]
    grep -qx "secrets_backend: vault" "$BATS_TEST_TMPDIR/orch-config/local.yaml"
    grep -qx "audit_sink: jsonl" "$BATS_TEST_TMPDIR/orch-config/local.yaml"
    grep -qx 'telegram_bridge_endpoint: "https://bridge.example/foo"' "$BATS_TEST_TMPDIR/orch-config/local.yaml"
}

@test "OP5 non-TTY with no env pre-answer and no piped input falls back to sane defaults" {
    run env HOME="$FAKE_HOME" DATARIM_ORCH_CONFIG_DIR="$BATS_TEST_TMPDIR/orch-config" \
        "$FAKE_REPO/install.sh" --profile orchestrator < /dev/null
    [ "$status" -eq 0 ]
    grep -qx "secrets_backend: yaml" "$BATS_TEST_TMPDIR/orch-config/local.yaml"
    grep -qx "audit_sink: jsonl" "$BATS_TEST_TMPDIR/orch-config/local.yaml"
    grep -qx 'telegram_bridge_endpoint: ""' "$BATS_TEST_TMPDIR/orch-config/local.yaml"
}

@test "OP6 idempotent: second run without --force preserves existing values" {
    run env HOME="$FAKE_HOME" DATARIM_ORCH_CONFIG_DIR="$BATS_TEST_TMPDIR/orch-config" \
        DATARIM_ORCH_SECRETS_BACKEND=vault DATARIM_ORCH_AUDIT_SINK=opsbot \
        DATARIM_ORCH_TELEGRAM_ENDPOINT="https://first.example" \
        "$FAKE_REPO/install.sh" --profile orchestrator
    [ "$status" -eq 0 ]

    run env HOME="$FAKE_HOME" DATARIM_ORCH_CONFIG_DIR="$BATS_TEST_TMPDIR/orch-config" \
        DATARIM_ORCH_SECRETS_BACKEND=yaml DATARIM_ORCH_AUDIT_SINK=jsonl \
        DATARIM_ORCH_TELEGRAM_ENDPOINT="https://second.example" \
        "$FAKE_REPO/install.sh" --profile orchestrator
    [ "$status" -eq 0 ]
    [[ "$output" == *"Preserving existing values"* ]]
    grep -qx "secrets_backend: vault" "$BATS_TEST_TMPDIR/orch-config/local.yaml"
    grep -qx 'telegram_bridge_endpoint: "https://first.example"' "$BATS_TEST_TMPDIR/orch-config/local.yaml"
}

@test "OP7 --force reconfigures and overwrites existing local.yaml" {
    run env HOME="$FAKE_HOME" DATARIM_ORCH_CONFIG_DIR="$BATS_TEST_TMPDIR/orch-config" \
        DATARIM_ORCH_SECRETS_BACKEND=vault DATARIM_ORCH_AUDIT_SINK=opsbot \
        DATARIM_ORCH_TELEGRAM_ENDPOINT="https://first.example" \
        "$FAKE_REPO/install.sh" --profile orchestrator
    [ "$status" -eq 0 ]

    run env HOME="$FAKE_HOME" DATARIM_ORCH_CONFIG_DIR="$BATS_TEST_TMPDIR/orch-config" \
        DATARIM_ORCH_SECRETS_BACKEND=yaml DATARIM_ORCH_AUDIT_SINK=jsonl \
        DATARIM_ORCH_TELEGRAM_ENDPOINT="https://second.example" \
        "$FAKE_REPO/install.sh" --profile orchestrator --force
    [ "$status" -eq 0 ]
    grep -qx "secrets_backend: yaml" "$BATS_TEST_TMPDIR/orch-config/local.yaml"
    grep -qx 'telegram_bridge_endpoint: "https://second.example"' "$BATS_TEST_TMPDIR/orch-config/local.yaml"
}

@test "OP8 invalid secrets backend value rejected with exit 2" {
    run env HOME="$FAKE_HOME" DATARIM_ORCH_CONFIG_DIR="$BATS_TEST_TMPDIR/orch-config" \
        DATARIM_ORCH_SECRETS_BACKEND=bogus \
        "$FAKE_REPO/install.sh" --profile orchestrator
    [ "$status" -eq 2 ]
    [[ "$output" == *"invalid secrets backend"* ]]
}

@test "OP9 invalid audit sink value rejected with exit 2" {
    run env HOME="$FAKE_HOME" DATARIM_ORCH_CONFIG_DIR="$BATS_TEST_TMPDIR/orch-config" \
        DATARIM_ORCH_AUDIT_SINK=bogus \
        "$FAKE_REPO/install.sh" --profile orchestrator
    [ "$status" -eq 2 ]
    [[ "$output" == *"invalid audit sink"* ]]
}

@test "OP10 unknown --profile value rejected with exit 2" {
    run env HOME="$FAKE_HOME" "$FAKE_REPO/install.sh" --profile bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown --profile value"* ]]
}

@test "OP11 config dir gets a self-contained .gitignore (never-commit convention)" {
    run env HOME="$FAKE_HOME" DATARIM_ORCH_CONFIG_DIR="$BATS_TEST_TMPDIR/orch-config" \
        DATARIM_ORCH_SECRETS_BACKEND=yaml \
        "$FAKE_REPO/install.sh" --profile orchestrator
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/orch-config/.gitignore" ]
    grep -qx '\*' "$BATS_TEST_TMPDIR/orch-config/.gitignore"
}

@test "OP12 --profile orchestrator with default HOME-derived config dir (no override)" {
    run env HOME="$FAKE_HOME" DATARIM_ORCH_SECRETS_BACKEND=yaml DATARIM_ORCH_AUDIT_SINK=jsonl \
        "$FAKE_REPO/install.sh" --profile orchestrator
    [ "$status" -eq 0 ]
    [ -f "$FAKE_HOME/.config/datarim-orchestrate/local.yaml" ]
}
