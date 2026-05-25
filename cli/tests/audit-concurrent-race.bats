#!/usr/bin/env bats
# V-AC-19 — 16-process concurrent append yields 16 valid JSONL lines, no torn writes.
# V-AC-5  — every line has 10 required keys with schema_version=1.
# Source: TUNE-0271 plan § Detailed Design 4.2.

setup() {
    CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    REPO_ROOT="$(cd "$CLI_DIR/.." && pwd)"
    AUDIT_LIB="$CLI_DIR/lib/audit.sh"
    UUID_GEN="$CLI_DIR/lib/uuid7-gen.sh"
    CHECK_SCRIPT="$REPO_ROOT/dev-tools/check-cli-audit-schema.sh"
    [ -f "$AUDIT_LIB" ] || skip "audit.sh missing"

    TMP_DIR="$(mktemp -d)"
    export DATARIM_CLI_AUDIT_DIR="$TMP_DIR/audit"
    export DATARIM_CLI_AGENT_ID
    DATARIM_CLI_AGENT_ID="$("$UUID_GEN")"
    export DATARIM_CLI_SESSION_ID="test-session-$$"
}

teardown() {
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR" || true
}

@test "V-AC-19: 16 parallel appends → 16 valid JSON lines, all 10 keys" {
    local pids=() i
    for i in $(seq 1 16); do
        (
            . "$AUDIT_LIB"
            hash="$(audit_args_hash "/dr-status" "arg$i")"
            audit_append "run" "$hash" "reversible" "success" "$((100 + i))" 0
        ) &
        pids+=($!)
    done
    for p in "${pids[@]}"; do wait "$p"; done

    local today_file
    today_file="$DATARIM_CLI_AUDIT_DIR/cli-audit-$(date -u +%F).jsonl"
    [ -f "$today_file" ]
    line_count=$(wc -l < "$today_file" | tr -d ' ')
    [ "$line_count" -eq 16 ]

    # Validate every line.
    run "$CHECK_SCRIPT" --day "$(date -u +%F)"
    [ "$status" -eq 0 ]
}

@test "V-AC-5: missing required key fails schema validator" {
    today_file="$DATARIM_CLI_AUDIT_DIR/cli-audit-$(date -u +%F).jsonl"
    mkdir -p "$DATARIM_CLI_AUDIT_DIR"
    # Hand-craft a line missing exit_code.
    printf '{"schema_version":1,"ts":"2026-05-23T00:00:00.000Z","session_id":"x","calling_agent":"y","subcommand":"run","args_hash":"sha256:%064x","reversibility":"reversible","outcome":"success","duration_ms":1}\n' 0 \
        > "$today_file"
    run "$CHECK_SCRIPT" --day "$(date -u +%F)"
    [ "$status" -eq 1 ]
}

@test "V-AC-5: invalid reversibility enum fails validator" {
    today_file="$DATARIM_CLI_AUDIT_DIR/cli-audit-$(date -u +%F).jsonl"
    mkdir -p "$DATARIM_CLI_AUDIT_DIR"
    printf '{"schema_version":1,"ts":"2026-05-23T00:00:00.000Z","session_id":"x","calling_agent":"y","subcommand":"run","args_hash":"sha256:%064x","reversibility":"maybe","outcome":"success","duration_ms":1,"exit_code":0}\n' 0 \
        > "$today_file"
    run "$CHECK_SCRIPT" --day "$(date -u +%F)"
    [ "$status" -eq 1 ]
}

@test "V-AC-5: invalid outcome enum fails validator" {
    today_file="$DATARIM_CLI_AUDIT_DIR/cli-audit-$(date -u +%F).jsonl"
    mkdir -p "$DATARIM_CLI_AUDIT_DIR"
    printf '{"schema_version":1,"ts":"2026-05-23T00:00:00.000Z","session_id":"x","calling_agent":"y","subcommand":"run","args_hash":"sha256:%064x","reversibility":"reversible","outcome":"meh","duration_ms":1,"exit_code":0}\n' 0 \
        > "$today_file"
    run "$CHECK_SCRIPT" --day "$(date -u +%F)"
    [ "$status" -eq 1 ]
}

@test "V-AC-5: args_hash bad shape fails validator" {
    today_file="$DATARIM_CLI_AUDIT_DIR/cli-audit-$(date -u +%F).jsonl"
    mkdir -p "$DATARIM_CLI_AUDIT_DIR"
    printf '{"schema_version":1,"ts":"2026-05-23T00:00:00.000Z","session_id":"x","calling_agent":"y","subcommand":"run","args_hash":"md5:abc","reversibility":"reversible","outcome":"success","duration_ms":1,"exit_code":0}\n' \
        > "$today_file"
    run "$CHECK_SCRIPT" --day "$(date -u +%F)"
    [ "$status" -eq 1 ]
}

@test "V-AC-5: opsbot_emit stub returns 99 (matches /dr-orchestrate pattern)" {
    run bash -c ". '$AUDIT_LIB'; opsbot_emit"
    [ "$status" -eq 99 ]
}
