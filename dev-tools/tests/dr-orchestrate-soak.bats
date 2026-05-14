#!/usr/bin/env bats
# dr-orchestrate-soak.bats — regression coverage for dr-orchestrate-soak.sh
#
# Coverage:
#   T1  --help-ish: refuses to start when weights sum to 0 (exit 2)
#   T2  --help-ish: refuses to start when CMD path is non-executable (exit 2)
#   T3  short run with mock CMD respects DR_SOAK_DURATION_SECONDS
#   T4  cycle accounting matches stdout markers (cycle-begin == cycle-end count)
#   T5  weights bias is respected (W_RESOLVED=100 only emits resolved + noop=0)
#   T6  prompts come from corpus (no empty/garbled prompts in resolved/escalated)
#   T7  DR_SOAK_AUDIT_DIR exports DR_ORCH_AUDIT_DIR to child invocations
#
# Spec: TUNE-0209.

SOAK="$BATS_TEST_DIRNAME/../dr-orchestrate-soak.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    export TMPROOT
    MOCK="$TMPROOT/mock_cmd_run.sh"
    LOG="$TMPROOT/cmd-invocations.log"
    cat >"$MOCK" <<EOF
#!/usr/bin/env bash
echo "PID=\$\$ DR_ORCH_AUDIT_DIR=\${DR_ORCH_AUDIT_DIR:-unset} args: \$*" >> "$LOG"
exit 0
EOF
    chmod +x "$MOCK"
    export MOCK LOG
}

teardown() {
    [ -n "${TMPROOT:-}" ] && rm -rf "$TMPROOT"
}

@test "T1 weights sum to 0 → exit 2" {
    run env DR_SOAK_W_RESOLVED=0 DR_SOAK_W_ESCALATED=0 DR_SOAK_W_NOOP=0 \
        DR_SOAK_CMD="$MOCK" DR_SOAK_DURATION_SECONDS=2 "$SOAK"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "weights sum to 0" ]]
}

@test "T2 non-executable CMD → exit 2" {
    run env DR_SOAK_CMD=/nonexistent/path DR_SOAK_DURATION_SECONDS=2 "$SOAK"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "missing or not executable" ]]
}

@test "T3 short run respects DURATION_SECONDS" {
    start=$(date +%s)
    run env DR_SOAK_DURATION_SECONDS=3 DR_SOAK_CYCLE_SLEEP=1 DR_SOAK_CMD="$MOCK" "$SOAK"
    end=$(date +%s)
    [ "$status" -eq 0 ]
    elapsed=$((end - start))
    [ "$elapsed" -ge 3 ]
    [ "$elapsed" -le 6 ]
    [[ "$output" =~ "deadline reached" ]]
}

@test "T4 cycle-begin count equals cycle-end count" {
    run env DR_SOAK_DURATION_SECONDS=3 DR_SOAK_CYCLE_SLEEP=1 DR_SOAK_CMD="$MOCK" "$SOAK"
    [ "$status" -eq 0 ]
    begins=$(grep -c 'cycle-begin' <<<"$output")
    ends=$(grep -c 'cycle-end' <<<"$output")
    [ "$begins" -eq "$ends" ]
    [ "$begins" -ge 2 ]
}

@test "T5 W_RESOLVED=100 only emits resolved (no noop, no escalated)" {
    run env DR_SOAK_W_RESOLVED=100 DR_SOAK_W_ESCALATED=0 DR_SOAK_W_NOOP=0 \
        DR_SOAK_DURATION_SECONDS=3 DR_SOAK_CYCLE_SLEEP=1 DR_SOAK_CMD="$MOCK" "$SOAK"
    [ "$status" -eq 0 ]
    noop_count=$(grep -c 'mode=noop' <<<"$output" || true)
    esc_count=$(grep -c 'mode=escalated' <<<"$output" || true)
    res_count=$(grep -c 'mode=resolved' <<<"$output" || true)
    [ "$noop_count" -eq 0 ]
    [ "$esc_count" -eq 0 ]
    [ "$res_count" -ge 2 ]
}

@test "T6 prompts come from non-empty corpus" {
    run env DR_SOAK_W_RESOLVED=50 DR_SOAK_W_ESCALATED=50 DR_SOAK_W_NOOP=0 \
        DR_SOAK_DURATION_SECONDS=4 DR_SOAK_CYCLE_SLEEP=1 DR_SOAK_CMD="$MOCK" "$SOAK"
    [ "$status" -eq 0 ]
    [ -f "$LOG" ]
    empty_prompts=$(grep -c -- '--unknown-prompt $' "$LOG" || true)
    [ "$empty_prompts" -eq 0 ]
    prompts=$(grep -c -- '--unknown-prompt' "$LOG" || true)
    [ "$prompts" -ge 2 ]
}

@test "T7 DR_SOAK_AUDIT_DIR exports DR_ORCH_AUDIT_DIR to child" {
    custom="$TMPROOT/custom-audit"
    run env DR_SOAK_AUDIT_DIR="$custom" \
        DR_SOAK_W_RESOLVED=100 DR_SOAK_W_ESCALATED=0 DR_SOAK_W_NOOP=0 \
        DR_SOAK_DURATION_SECONDS=2 DR_SOAK_CYCLE_SLEEP=1 DR_SOAK_CMD="$MOCK" "$SOAK"
    [ "$status" -eq 0 ]
    [ -f "$LOG" ]
    grep -q "DR_ORCH_AUDIT_DIR=$custom" "$LOG"
}
