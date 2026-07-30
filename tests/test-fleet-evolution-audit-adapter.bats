#!/usr/bin/env bats
# tests/test-fleet-evolution-audit-adapter.bats — audit-log source adapter +
# redaction layer for the fleet skill-evolution loop.

bats_require_minimum_version 1.5.0

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ADAPTER="$REPO/plugins/dr-fleet-evolution/adapters/audit-log-adapter.sh"
    REDACT_LIB="$REPO/plugins/dr-fleet-evolution/lib/redact.sh"
    TMP="$BATS_TEST_TMPDIR"
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available — adapter requires jq for JSONL emission"
    fi

    # A mock redis client. Its behaviour is driven by env:
    #   REDIS_MOCK_PONG   — if "0", `ping` returns FAIL instead of PONG.
    #   REDIS_MOCK_DATA   — file whose contents are echoed for the EVAL flatten
    #                       call (one entry per line, TAB-separated k=v tokens).
    MOCK="$TMP/redis-cli-mock.sh"
    cat > "$MOCK" <<'EOF'
#!/usr/bin/env bash
# crude arg scan: locate the redis subcommand (ping | EVAL)
for a in "$@"; do
    case "$a" in
        ping|PING) if [ "${REDIS_MOCK_PONG:-1}" = "0" ]; then echo "FAIL"; else echo "PONG"; fi; exit 0 ;;
        eval|EVAL) cat "$REDIS_MOCK_DATA" 2>/dev/null; exit 0 ;;
    esac
done
exit 0
EOF
    chmod +x "$MOCK"

    # Canonical audit-log entries. Entry 1 carries deliberately sensitive
    # traces in its reason field (secret token, absolute path, mesh hostname,
    # IPv4, ssh user@host) that MUST be scrubbed before the record is emitted.
    DATA="$TMP/audit-data.tsv"
    printf '%s\n' \
"1700000000000-0	id=uuid-1	ts=2026-07-21T00:00:00Z	type=audit	task_id=DEMO-0001	reason=ran ssh dev@arcana-devs cat /home/dev/secret/key -- token=SECRET123abc against 10.1.2.3	outcome=success" \
"1700000000001-0	id=uuid-2	ts=2026-07-21T00:01:00Z	type=agent-killed	task_id=DEMO-0002	reason=killed after SLA timeout" \
        > "$DATA"
}

# ── standalone contract (no Redis needed) ─────────────────────────────────────

@test "audit-log-adapter is executable" {
    [ -x "$ADAPTER" ]
}

@test "audit-log-adapter exits 2 on usage error (no arg)" {
    run "$ADAPTER"
    [ "$status" -eq 2 ]
}

@test "audit-log-adapter --help exits 0" {
    run "$ADAPTER" --help
    [ "$status" -eq 0 ]
}

# ── env-gated skip (Redis absent / unreachable) ───────────────────────────────

@test "audit-log-adapter skips (exit 0, empty stdout) when redis-cli is absent" {
    # --separate-stderr: the skip note is on stderr; the contract governs stdout.
    REDIS_CLI_BIN="/nonexistent/redis-cli" run --separate-stderr "$ADAPTER" "redis://127.0.0.1:6379"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "audit-log-adapter skips (exit 0, empty stdout) when redis ping fails" {
    REDIS_CLI_BIN="$MOCK" REDIS_MOCK_PONG=0 run --separate-stderr "$ADAPTER" "redis://127.0.0.1:6379"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ── JSONL contract ────────────────────────────────────────────────────────────

@test "audit-log-adapter emits valid JSONL, one record per audit entry" {
    REDIS_CLI_BIN="$MOCK" REDIS_MOCK_DATA="$DATA" run "$ADAPTER" "redis://127.0.0.1:6379"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
    printf '%s\n' "$output" | while IFS= read -r l; do
        [ -z "$l" ] && continue
        printf '%s' "$l" | jq -e 'has("task_input") and has("expected_output") and has("actual_output") and has("outcome") and .source=="audit-log"'
    done
}

@test "audit-log-adapter derives failure for an agent-killed entry" {
    REDIS_CLI_BIN="$MOCK" REDIS_MOCK_DATA="$DATA" run "$ADAPTER" "redis://127.0.0.1:6379"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -F 'DEMO-0002' | jq -e '.outcome=="failure"'
}

@test "audit-log-adapter derives success for a clean audit entry" {
    REDIS_CLI_BIN="$MOCK" REDIS_MOCK_DATA="$DATA" run "$ADAPTER" "redis://127.0.0.1:6379"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -F 'DEMO-0001' | jq -e '.outcome=="success"'
}

# ── redaction (Security S1) — the sensitive token MUST NOT reach the dataset ──

@test "redaction: no sensitive trace survives into the emitted dataset" {
    REDIS_CLI_BIN="$MOCK" REDIS_MOCK_DATA="$DATA" run "$ADAPTER" "redis://127.0.0.1:6379"
    [ "$status" -eq 0 ]
    # secret material
    ! printf '%s' "$output" | grep -q 'SECRET123abc'
    # absolute path
    ! printf '%s' "$output" | grep -q '/home/dev/secret'
    # mesh hostname
    ! printf '%s' "$output" | grep -q 'arcana-devs'
    # IPv4 address
    ! printf '%s' "$output" | grep -q '10.1.2.3'
}

@test "redaction: scrubbed reason still carries the placeholder markers" {
    REDIS_CLI_BIN="$MOCK" REDIS_MOCK_DATA="$DATA" run "$ADAPTER" "redis://127.0.0.1:6379"
    [ "$status" -eq 0 ]
    printf '%s' "$output" | grep -q '<REDACTED>'
    printf '%s' "$output" | grep -q '<PATH>'
    printf '%s' "$output" | grep -q '<HOST>'
}

# ── redaction library (unit) ──────────────────────────────────────────────────

@test "redact_trace scrubs secrets, paths, hosts and IPs" {
    source "$REDACT_LIB"
    local out
    out=$(redact_trace 'ssh dev@arcana-prod token=abc123XYZ path /var/lib/foo host db.arcanada.club ip 192.168.0.5')
    ! printf '%s' "$out" | grep -q 'abc123XYZ'
    ! printf '%s' "$out" | grep -q '/var/lib/foo'
    ! printf '%s' "$out" | grep -q 'arcana-prod'
    ! printf '%s' "$out" | grep -q 'db.arcanada.club'
    ! printf '%s' "$out" | grep -q '192.168.0.5'
}

@test "redact_trace leaves benign text intact" {
    source "$REDACT_LIB"
    local out
    out=$(redact_trace 'stage plan completed in 3 steps')
    [ "$out" = 'stage plan completed in 3 steps' ]
}

@test "redact_trace scrubs space-separated Bearer tokens and known secret prefixes" {
    source "$REDACT_LIB"
    local out
    out=$(redact_trace 'Authorization: Bearer ghp_ABC123deadbeefTOKEN calling with sk-liveKEY0987 and xoxb-99-slackSECRET')
    ! printf '%s' "$out" | grep -q 'ghp_ABC123deadbeefTOKEN'
    ! printf '%s' "$out" | grep -q 'sk-liveKEY0987'
    ! printf '%s' "$out" | grep -q 'xoxb-99-slackSECRET'
}
