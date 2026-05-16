#!/usr/bin/env bats
# preflight-check.bats — INFRA-0122 / INFRA-0121 Phase 1
#
# Coverage:
#   T01-T04 check_disk         (ok / warn-percent / fatal-percent / low-free-gb)
#   T05-T06 check_tailscale    (ok / down)
#   T07-T08 check_vault        (ok / sealed)
#   T09-T10 check_docker       (ok / high reclaimable)
#   T11-T12 check_ram          (ok / low free)
#   T13-T14 check_loadavg      (ok / fatal)
#   T15     check_time_skew    (warn — never blocks)
#   T16-T17 check_health       (ok / down)
#   T18     append_finding     (json mutation + counters)
#   T19     emit_ops_bot       (canonical DTO payload shape)
#   T20     emit_ops_bot       (fail-soft on missing OPSBOT_KEY)
#   T21     per-host override  (PREFLIGHT_ARCANA_PROD_MIN_FREE_DISK_GB)
#   T22     fail-closed missing target-host
#   T23     input regex rejection
#   T24     end-to-end OK exit 0
#   T25     end-to-end FATAL exit 2
#   T26     end-to-end MIXED status=warn exit 0

SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/preflight-check.sh"
FIX="$BATS_TEST_DIRNAME/fixtures/preflight"

setup() {
    TMPROOT="$(mktemp -d)"
    export TMPROOT
    MOCK_BIN="$TMPROOT/mock-bin"
    mkdir -p "$MOCK_BIN"
    export MOCK_BIN
    REPORT_FILE="$TMPROOT/report.json"
    export REPORT_FILE
    echo "[]" > "$REPORT_FILE"
    CURL_LOG="$TMPROOT/curl.log"
    export CURL_LOG

    # Required env for sourcing the script without running main
    export PREFLIGHT_TARGET_HOST="arcana-prod"
    export PREFLIGHT_SERVICE_NAME="opsbot"
    export PREFLIGHT_TEST_MODE=1
    export GITHUB_OUTPUT="$TMPROOT/gha_output"
    : > "$GITHUB_OUTPUT"
}

teardown() {
    [ -n "${TMPROOT:-}" ] && rm -rf "$TMPROOT"
}

# Build a mock command on PATH that emits fixture file content.
mock_cmd_file() {
    local name="$1" fixture="$2"
    cat > "$MOCK_BIN/$name" <<EOF
#!/usr/bin/env bash
cat "$fixture"
EOF
    chmod +x "$MOCK_BIN/$name"
}

# Build a mock that exits non-zero (simulate command-missing or hard fail).
mock_cmd_fail() {
    local name="$1" code="${2:-1}"
    cat > "$MOCK_BIN/$name" <<EOF
#!/usr/bin/env bash
exit $code
EOF
    chmod +x "$MOCK_BIN/$name"
}

# Build a curl mock that logs args + stdin and emits OK by default.
mock_curl() {
    cat > "$MOCK_BIN/curl" <<EOF
#!/usr/bin/env bash
echo "ARGS:" "\$@" >> "$CURL_LOG"
# Capture --data payload (next arg after -d)
prev=""
for a in "\$@"; do
    if [[ "\$prev" == "-d" || "\$prev" == "--data" ]]; then
        echo "PAYLOAD:" "\$a" >> "$CURL_LOG"
    fi
    prev="\$a"
done
exit 0
EOF
    chmod +x "$MOCK_BIN/curl"
}

prepend_path() {
    export PATH="$MOCK_BIN:$PATH"
}

source_script() {
    # shellcheck disable=SC1090
    source "$SCRIPT"
}

# ---------- check_disk ----------

@test "T01 check_disk: ok (disk usage 20%, 160 GB free)" {
    mock_cmd_file df "$FIX/df-ok.txt"
    prepend_path
    source_script
    run check_disk
    [ "$status" -eq 0 ]
    findings=$(jq 'length' "$REPORT_FILE")
    [ "$findings" -gt 0 ]
    fatal=$(jq '[.[] | select(.status=="fatal")] | length' "$REPORT_FILE")
    warn=$(jq  '[.[] | select(.status=="warning")] | length' "$REPORT_FILE")
    [ "$fatal" -eq 0 ]
    [ "$warn" -eq 0 ]
}

@test "T02 check_disk: warn (usage 83-88%, above warn-percent 80)" {
    mock_cmd_file df "$FIX/df-warn.txt"
    prepend_path
    source_script
    run check_disk
    [ "$status" -eq 0 ]
    warn=$(jq '[.[] | select(.status=="warning")] | length' "$REPORT_FILE")
    [ "$warn" -gt 0 ]
}

@test "T03 check_disk: fatal (usage 95%, above fail-percent 90)" {
    mock_cmd_file df "$FIX/df-fatal.txt"
    prepend_path
    source_script
    run check_disk
    fatal=$(jq '[.[] | select(.status=="fatal")] | length' "$REPORT_FILE")
    [ "$fatal" -gt 0 ]
}

@test "T04 check_disk: fatal on free-GB below min (usage 99%, free 1GB < 2GB)" {
    mock_cmd_file df "$FIX/df-low-free.txt"
    prepend_path
    source_script
    run check_disk
    fatal=$(jq '[.[] | select(.status=="fatal" and .metric=="free_gb")] | length' "$REPORT_FILE")
    [ "$fatal" -gt 0 ]
}

# ---------- check_tailscale ----------

@test "T05 check_tailscale: ok (BackendState=Running, Self.Online=true)" {
    mock_cmd_file tailscale "$FIX/tailscale-ok.json"
    prepend_path
    source_script
    run check_tailscale
    [ "$status" -eq 0 ]
    fatal=$(jq '[.[] | select(.name=="tailscale" and .status=="fatal")] | length' "$REPORT_FILE")
    [ "$fatal" -eq 0 ]
}

@test "T06 check_tailscale: fatal (BackendState=Stopped)" {
    mock_cmd_file tailscale "$FIX/tailscale-down.json"
    prepend_path
    source_script
    run check_tailscale
    fatal=$(jq '[.[] | select(.name=="tailscale" and .status=="fatal")] | length' "$REPORT_FILE")
    [ "$fatal" -gt 0 ]
}

# ---------- check_vault ----------

@test "T07 check_vault: ok (initialized, sealed=false)" {
    mock_cmd_file vault "$FIX/vault-ok.json"
    prepend_path
    source_script
    run check_vault
    fatal=$(jq '[.[] | select(.name=="vault" and .status=="fatal")] | length' "$REPORT_FILE")
    [ "$fatal" -eq 0 ]
}

@test "T08 check_vault: fatal (sealed=true)" {
    mock_cmd_file vault "$FIX/vault-sealed.json"
    export PREFLIGHT_VAULT_RETRIES=1
    export PREFLIGHT_VAULT_RETRY_DELAY=0
    prepend_path
    source_script
    run check_vault
    fatal=$(jq '[.[] | select(.name=="vault" and .status=="fatal")] | length' "$REPORT_FILE")
    [ "$fatal" -gt 0 ]
}

# ---------- check_docker_pressure ----------

@test "T09 check_docker_pressure: ok (reclaimable < 10GB)" {
    mock_cmd_file docker "$FIX/docker-df-ok.json"
    prepend_path
    source_script
    run check_docker_pressure
    warn=$(jq '[.[] | select(.name=="docker_pressure" and .status=="warning")] | length' "$REPORT_FILE")
    [ "$warn" -eq 0 ]
}

@test "T10 check_docker_pressure: warn (reclaimable > 10GB)" {
    mock_cmd_file docker "$FIX/docker-df-high.json"
    prepend_path
    source_script
    run check_docker_pressure
    warn=$(jq '[.[] | select(.name=="docker_pressure" and .status=="warning")] | length' "$REPORT_FILE")
    [ "$warn" -gt 0 ]
}

# ---------- check_ram_swap ----------

@test "T11 check_ram_swap: ok (free 14GB > 500MB threshold)" {
    mock_cmd_file free "$FIX/free-ok.txt"
    prepend_path
    source_script
    run check_ram_swap
    fatal=$(jq '[.[] | select(.name=="ram_swap" and .status=="fatal")] | length' "$REPORT_FILE")
    [ "$fatal" -eq 0 ]
}

@test "T12 check_ram_swap: fatal (free 200MB < 500MB threshold)" {
    mock_cmd_file free "$FIX/free-low.txt"
    prepend_path
    source_script
    run check_ram_swap
    fatal=$(jq '[.[] | select(.name=="ram_swap" and .status=="fatal")] | length' "$REPORT_FILE")
    [ "$fatal" -gt 0 ]
}

# ---------- check_loadavg ----------

@test "T13 check_loadavg: ok (5min 0.65 < nproc)" {
    mock_cmd_file uptime "$FIX/uptime-ok.txt"
    cat > "$MOCK_BIN/nproc" <<'EOF'
#!/usr/bin/env bash
echo 4
EOF
    chmod +x "$MOCK_BIN/nproc"
    prepend_path
    source_script
    run check_loadavg
    fatal=$(jq '[.[] | select(.name=="loadavg" and .status=="fatal")] | length' "$REPORT_FILE")
    warn=$(jq  '[.[] | select(.name=="loadavg" and .status=="warning")] | length' "$REPORT_FILE")
    [ "$fatal" -eq 0 ]
    [ "$warn" -eq 0 ]
}

@test "T14 check_loadavg: fatal (5min 11.20 > 2x nproc=4)" {
    mock_cmd_file uptime "$FIX/uptime-fatal.txt"
    cat > "$MOCK_BIN/nproc" <<'EOF'
#!/usr/bin/env bash
echo 4
EOF
    chmod +x "$MOCK_BIN/nproc"
    prepend_path
    source_script
    run check_loadavg
    fatal=$(jq '[.[] | select(.name=="loadavg" and .status=="fatal")] | length' "$REPORT_FILE")
    [ "$fatal" -gt 0 ]
}

# ---------- check_time_skew ----------

@test "T15 check_time_skew: warn but never fatal (offset 1.234 > 0.5s)" {
    mock_cmd_file chronyc "$FIX/chrony-skew.txt"
    prepend_path
    source_script
    run check_time_skew
    fatal=$(jq '[.[] | select(.name=="time_skew" and .status=="fatal")] | length' "$REPORT_FILE")
    warn=$(jq  '[.[] | select(.name=="time_skew" and .status=="warning")] | length' "$REPORT_FILE")
    [ "$fatal" -eq 0 ]
    [ "$warn" -gt 0 ]
}

# ---------- check_health_pre_probe ----------

@test "T16 check_health_pre_probe: ok (curl returns status=ok)" {
    cat > "$MOCK_BIN/curl" <<EOF
#!/usr/bin/env bash
cat "$FIX/health-ok.json"
EOF
    chmod +x "$MOCK_BIN/curl"
    prepend_path
    export PREFLIGHT_HEALTH_URL="http://localhost:9999/health"
    source_script
    run check_health_pre_probe
    warn=$(jq '[.[] | select(.name=="health_pre_probe" and .status=="warning")] | length' "$REPORT_FILE")
    [ "$warn" -eq 0 ]
}

@test "T17 check_health_pre_probe: warn (curl exits non-zero)" {
    mock_cmd_fail curl 22
    prepend_path
    export PREFLIGHT_HEALTH_URL="http://localhost:9999/health"
    source_script
    run check_health_pre_probe
    warn=$(jq '[.[] | select(.name=="health_pre_probe" and .status=="warning")] | length' "$REPORT_FILE")
    [ "$warn" -gt 0 ]
}

# ---------- append_finding ----------

@test "T18 append_finding: appends to JSON array, increments counters" {
    source_script
    WARN_COUNT=0
    FATAL_COUNT=0
    append_finding "disk" "warning" "used_pct" "85" "80"
    append_finding "vault" "fatal" "sealed" "true" "false"
    append_finding "tailscale" "ok" "online" "true" "true"
    n=$(jq 'length' "$REPORT_FILE")
    [ "$n" -eq 3 ]
    [ "$WARN_COUNT" -eq 1 ]
    [ "$FATAL_COUNT" -eq 1 ]
    name=$(jq -r '.[1].name' "$REPORT_FILE")
    [ "$name" = "vault" ]
}

# ---------- emit_ops_bot ----------

@test "T19 emit_ops_bot: canonical DTO payload shape" {
    mock_curl
    prepend_path
    export OPSBOT_KEY="testkey"
    export PREFLIGHT_RUN_URL="https://example/run/1"
    source_script
    append_finding "disk" "fatal" "free_gb" "1.2" "2.0"
    run emit_ops_bot "fail" "$REPORT_FILE"
    [ "$status" -eq 0 ]
    payload_line=$(grep "^PAYLOAD:" "$CURL_LOG" | head -1)
    [ -n "$payload_line" ]
    payload="${payload_line#PAYLOAD: }"
    agent=$(echo "$payload" | jq -r '.agent')
    title=$(echo "$payload" | jq -r '.title')
    category=$(echo "$payload" | jq -r '.category')
    dedup=$(echo "$payload" | jq -r '.dedup_key')
    host=$(echo "$payload" | jq -r '.meta.host')
    service=$(echo "$payload" | jq -r '.meta.service')
    audit=$(echo "$payload" | jq -r '.meta.audit_ref')
    checks_len=$(echo "$payload" | jq '.meta.checks | length')
    [ "$agent" = "preflight-check" ]
    [[ "$title" == *"opsbot"* ]]
    [[ "$title" == *"arcana-prod"* ]]
    [[ "$title" == *"FAIL"* ]]
    [ "$category" = "fatal" ]
    [[ "$dedup" == preflight-arcana-prod-opsbot-* ]]
    [ "$host" = "arcana-prod" ]
    [ "$service" = "opsbot" ]
    [ "$audit" = "https://example/run/1" ]
    [ "$checks_len" -ge 1 ]
}

@test "T20 emit_ops_bot: fail-soft when OPSBOT_KEY unset" {
    mock_curl
    prepend_path
    unset OPSBOT_KEY
    source_script
    append_finding "disk" "fatal" "free_gb" "1.2" "2.0"
    run emit_ops_bot "fail" "$REPORT_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OPSBOT_KEY"* ]]
    if [ -f "$CURL_LOG" ]; then
        n=$(wc -l < "$CURL_LOG" | tr -d ' ')
        [ "$n" -eq 0 ]
    fi
}

# ---------- per-host override ----------

@test "T21 per-host override: PREFLIGHT_ARCANA_PROD_MIN_FREE_DISK_GB=200" {
    mock_cmd_file df "$FIX/df-ok.txt"
    prepend_path
    export PREFLIGHT_ARCANA_PROD_MIN_FREE_DISK_GB=200
    export PREFLIGHT_TARGET_HOST=arcana-prod
    source_script
    run check_disk
    fatal=$(jq '[.[] | select(.name=="disk" and .status=="fatal" and .metric=="free_gb")] | length' "$REPORT_FILE")
    [ "$fatal" -gt 0 ]
}

# ---------- fail-closed ----------

@test "T22 fail-closed: missing PREFLIGHT_TARGET_HOST aborts script" {
    unset PREFLIGHT_TARGET_HOST
    run env -i PATH="$PATH" PREFLIGHT_SERVICE_NAME=opsbot bash "$SCRIPT"
    [ "$status" -ne 0 ]
}

# ---------- input regex ----------

@test "T23 input validation: bad target-host (uppercase) rejected" {
    run env PREFLIGHT_TARGET_HOST="ARCANA;rm -rf /" PREFLIGHT_SERVICE_NAME="opsbot" \
        PREFLIGHT_EXTRA_CHECKS="" PREFLIGHT_OPS_BOT_EMIT=false \
        GITHUB_OUTPUT="$GITHUB_OUTPUT" \
        bash "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid"* || "$output" == *"target-host"* || "$output" == *"target_host"* ]]
}

# ---------- end-to-end ----------

@test "T24 e2e: all-OK exit 0, status=ok" {
    mock_cmd_file df "$FIX/df-ok.txt"
    mock_cmd_file tailscale "$FIX/tailscale-ok.json"
    mock_cmd_file vault "$FIX/vault-ok.json"
    mock_cmd_file chronyc "$FIX/chrony-ok.txt"
    cat > "$MOCK_BIN/nproc" <<'EOF'
#!/usr/bin/env bash
echo 4
EOF
    chmod +x "$MOCK_BIN/nproc"
    prepend_path
    run env PATH="$PATH" \
        PREFLIGHT_TARGET_HOST=arcana-prod \
        PREFLIGHT_SERVICE_NAME=opsbot \
        PREFLIGHT_EXTRA_CHECKS=$'vault\ntailscale\ntime-skew' \
        PREFLIGHT_OPS_BOT_EMIT=false \
        GITHUB_OUTPUT="$GITHUB_OUTPUT" \
        bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q "^status=ok$" "$GITHUB_OUTPUT"
    grep -q "^failures=0$" "$GITHUB_OUTPUT"
}

@test "T25 e2e: disk-fatal exits 2, status=fail" {
    mock_cmd_file df "$FIX/df-fatal.txt"
    mock_cmd_file tailscale "$FIX/tailscale-ok.json"
    mock_cmd_file vault "$FIX/vault-ok.json"
    mock_cmd_file chronyc "$FIX/chrony-ok.txt"
    prepend_path
    run env PATH="$PATH" \
        PREFLIGHT_TARGET_HOST=arcana-prod \
        PREFLIGHT_SERVICE_NAME=opsbot \
        PREFLIGHT_EXTRA_CHECKS=$'vault\ntailscale\ntime-skew' \
        PREFLIGHT_OPS_BOT_EMIT=false \
        GITHUB_OUTPUT="$GITHUB_OUTPUT" \
        bash "$SCRIPT"
    [ "$status" -eq 2 ]
    grep -q "^status=fail$" "$GITHUB_OUTPUT"
}

@test "T34 e2e: warn-only exits 0, status=warn" {
    mock_cmd_file df "$FIX/df-warn.txt"
    mock_cmd_file tailscale "$FIX/tailscale-ok.json"
    mock_cmd_file vault "$FIX/vault-ok.json"
    mock_cmd_file chronyc "$FIX/chrony-ok.txt"
    prepend_path
    run env PATH="$PATH" \
        PREFLIGHT_TARGET_HOST=arcana-prod \
        PREFLIGHT_SERVICE_NAME=opsbot \
        PREFLIGHT_EXTRA_CHECKS=$'vault\ntailscale\ntime-skew' \
        PREFLIGHT_OPS_BOT_EMIT=false \
        GITHUB_OUTPUT="$GITHUB_OUTPUT" \
        bash "$SCRIPT"
    [ "$status" -eq 0 ]
    grep -q "^status=warn$" "$GITHUB_OUTPUT"
    grep -q "^failures=0$" "$GITHUB_OUTPUT"
    warns=$(grep "^warnings=" "$GITHUB_OUTPUT" | cut -d= -f2)
    [ "$warns" -gt 0 ]
}

# ---------- INFRA-0201: action.yml input-validation hardening ----------
#
# T23a/T23b — ops-bot-url allowlist guard (PROD strict, non-PROD WARN)
# T26-T29   — severity-overrides jq schema gate
# T30       — ops-bot-key → OPSBOT_KEY env propagation (action.yml literal)
#
# Validation logic lives in dev-tools/preflight-validate-{url,overrides}.sh
# (extracted from action.yml composite steps for testability).

VAL_URL="$BATS_TEST_DIRNAME/../dev-tools/preflight-validate-url.sh"
VAL_OVR="$BATS_TEST_DIRNAME/../dev-tools/preflight-validate-overrides.sh"
ACTION_YML="$BATS_TEST_DIRNAME/../.github/actions/preflight-check/action.yml"

@test "T23a ops-bot-url allowlist: PROD + canonical accepts (exit 0)" {
    run env \
        PREFLIGHT_OPS_BOT_URL=https://ops.arcanada.one/events \
        PREFLIGHT_IS_PROD_CONTEXT=true \
        bash "$VAL_URL"
    [ "$status" -eq 0 ]
}

@test "T23b ops-bot-url allowlist: PROD + non-canonical rejects (exit 1)" {
    run env \
        PREFLIGHT_OPS_BOT_URL=https://evil.example.com/events \
        PREFLIGHT_IS_PROD_CONTEXT=true \
        bash "$VAL_URL"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must match canonical"* ]]
}

@test "T26 severity-overrides: valid JSON exports PREFLIGHT_<KEY>=val to GITHUB_ENV" {
    GITHUB_ENV_FILE="$TMPROOT/github_env"
    : > "$GITHUB_ENV_FILE"
    run env \
        PREFLIGHT_SEVERITY_OVERRIDES="$(cat "$FIX/severity-overrides-valid.json")" \
        GITHUB_ENV="$GITHUB_ENV_FILE" \
        bash "$VAL_OVR"
    [ "$status" -eq 0 ]
    grep -q '^PREFLIGHT_MIN_FREE_DISK_GB=5$' "$GITHUB_ENV_FILE"
    grep -q '^PREFLIGHT_DISK_WARN_PERCENT=75$' "$GITHUB_ENV_FILE"
    grep -q '^PREFLIGHT_DISK_FAIL_PERCENT=85$' "$GITHUB_ENV_FILE"
}

@test "T27 severity-overrides: non-object JSON rejects (exit 1)" {
    run env \
        PREFLIGHT_SEVERITY_OVERRIDES="$(cat "$FIX/severity-overrides-non-object.json")" \
        GITHUB_ENV=/dev/null \
        bash "$VAL_OVR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be a JSON object"* ]]
}

@test "T28 severity-overrides: non-allowlisted key rejects (exit 1)" {
    run env \
        PREFLIGHT_SEVERITY_OVERRIDES="$(cat "$FIX/severity-overrides-invalid-key.json")" \
        GITHUB_ENV=/dev/null \
        bash "$VAL_OVR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not in allowlist"* ]]
}

@test "T29 severity-overrides: non-integer value rejects (exit 1)" {
    run env \
        PREFLIGHT_SEVERITY_OVERRIDES='{"min_free_disk_gb": 5.5}' \
        GITHUB_ENV=/dev/null \
        bash "$VAL_OVR"
    [ "$status" -eq 1 ]
    [[ "$output" == *"must be integer"* ]]
}

@test "T30 ops-bot-key: action.yml declares input + env-override expression" {
    [ -f "$ACTION_YML" ]
    grep -qE '^  ops-bot-key:' "$ACTION_YML"
    grep -qE 'OPSBOT_KEY: \$\{\{ inputs\.ops-bot-key != .. && inputs\.ops-bot-key \|\| env\.OPSBOT_KEY \}\}' "$ACTION_YML"
}
