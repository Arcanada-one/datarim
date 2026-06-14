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

@test "T6 prompts come from non-empty corpus (escalated path via --unknown-prompt)" {
    # Escalated prompts always use --unknown-prompt. Verify no empty prompt strings.
    run env DR_SOAK_W_RESOLVED=0 DR_SOAK_W_ESCALATED=100 DR_SOAK_W_NOOP=0 \
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

# ---------------------------------------------------------------------------
# T8-T12  seed-resolved routing + expected_outcome tagging (Phase 1 / Phase 2)
# ---------------------------------------------------------------------------

# T8: /dr-* resolved prompts must NOT be passed via --unknown-prompt; instead
# the soak driver seeds them via DR_ORCH_PANE_CAPTURE_OVERRIDE (no --unknown-prompt
# on the cmd invocation line for slash prompts when W_ESCALATED=0).
@test "T8 seed_resolved: slash prompts routed WITHOUT --unknown-prompt" {
    run env DR_SOAK_W_RESOLVED=100 DR_SOAK_W_ESCALATED=0 DR_SOAK_W_NOOP=0 \
        DR_SOAK_DURATION_SECONDS=3 DR_SOAK_CYCLE_SLEEP=1 DR_SOAK_CMD="$MOCK" "$SOAK"
    [ "$status" -eq 0 ]
    [ -f "$LOG" ]
    # None of the slash-command invocations should carry --unknown-prompt
    slash_with_unknown=$(grep -- '--unknown-prompt /dr-' "$LOG" || true)
    [ -z "$slash_with_unknown" ]
    # But resolved invocations must still happen
    invocations=$(grep -c 'args:' "$LOG" || true)
    [ "$invocations" -ge 2 ]
}

# T9: DR_ORCH_PANE_CAPTURE_OVERRIDE is set for resolved /dr-* calls in child env
@test "T9 seed_resolved: DR_ORCH_PANE_CAPTURE_OVERRIDE set for slash prompts" {
    # Capture env variables from child invocations
    MOCK2="$TMPROOT/mock_env.sh"
    LOG2="$TMPROOT/env-invocations.log"
    cat >"$MOCK2" <<'MOCKEOF'
#!/usr/bin/env bash
echo "OVERRIDE=${DR_ORCH_PANE_CAPTURE_OVERRIDE:-unset} args: $*" >> "$1"
exit 0
MOCKEOF
    chmod +x "$MOCK2"
    # Wrap mock to pass log path as env instead of arg
    MOCK3="$TMPROOT/mock_wrap.sh"
    cat >"$MOCK3" <<WEOF
#!/usr/bin/env bash
echo "OVERRIDE=\${DR_ORCH_PANE_CAPTURE_OVERRIDE:-unset} args: \$*" >> "$LOG2"
exit 0
WEOF
    chmod +x "$MOCK3"
    run env DR_SOAK_W_RESOLVED=100 DR_SOAK_W_ESCALATED=0 DR_SOAK_W_NOOP=0 \
        DR_SOAK_DURATION_SECONDS=3 DR_SOAK_CYCLE_SLEEP=1 DR_SOAK_CMD="$MOCK3" "$SOAK"
    [ "$status" -eq 0 ]
    [ -f "$LOG2" ]
    # At least one invocation must have a non-unset OVERRIDE value starting with /dr-
    overrides=$(grep 'OVERRIDE=/dr-' "$LOG2" || true)
    [ -n "$overrides" ]
}

# T10: expected_outcome=resolved is exported for resolved corpus calls
@test "T10 expected_outcome_tag: resolved corpus exports expected_outcome=resolved" {
    MOCK4="$TMPROOT/mock_outcome.sh"
    LOG4="$TMPROOT/outcome-invocations.log"
    cat >"$MOCK4" <<MEOF
#!/usr/bin/env bash
echo "EXPECTED=\${DR_ORCH_EXPECTED_OUTCOME:-unset} args: \$*" >> "$LOG4"
exit 0
MEOF
    chmod +x "$MOCK4"
    run env DR_SOAK_W_RESOLVED=100 DR_SOAK_W_ESCALATED=0 DR_SOAK_W_NOOP=0 \
        DR_SOAK_DURATION_SECONDS=3 DR_SOAK_CYCLE_SLEEP=1 DR_SOAK_CMD="$MOCK4" "$SOAK"
    [ "$status" -eq 0 ]
    [ -f "$LOG4" ]
    resolved_tagged=$(grep 'EXPECTED=resolved' "$LOG4" || true)
    [ -n "$resolved_tagged" ]
    # Must not have unset/empty EXPECTED for resolved calls
    unset_resolved=$(grep 'EXPECTED=unset' "$LOG4" || true)
    [ -z "$unset_resolved" ]
}

# T11: expected_outcome=escalated is exported for escalated corpus calls
@test "T11 expected_outcome_tag: escalated corpus exports expected_outcome=escalated" {
    MOCK5="$TMPROOT/mock_esc_outcome.sh"
    LOG5="$TMPROOT/esc-outcome-invocations.log"
    cat >"$MOCK5" <<MEOF
#!/usr/bin/env bash
echo "EXPECTED=\${DR_ORCH_EXPECTED_OUTCOME:-unset} args: \$*" >> "$LOG5"
exit 0
MEOF
    chmod +x "$MOCK5"
    run env DR_SOAK_W_RESOLVED=0 DR_SOAK_W_ESCALATED=100 DR_SOAK_W_NOOP=0 \
        DR_SOAK_DURATION_SECONDS=3 DR_SOAK_CYCLE_SLEEP=1 DR_SOAK_CMD="$MOCK5" "$SOAK"
    [ "$status" -eq 0 ]
    [ -f "$LOG5" ]
    esc_tagged=$(grep 'EXPECTED=escalated' "$LOG5" || true)
    [ -n "$esc_tagged" ]
}

# T12: measure refined formula counts only expected_outcome==resolved events
@test "T12 measure_refined_formula: counts only resolved-expected events" {
    MEASURE="$BATS_TEST_DIRNAME/../measure-orchestrator-soak.sh"
    AUDIT="$TMPROOT/measure-fixture"
    mkdir -p "$AUDIT"
    AFILE="$AUDIT/audit-2099-01-01.jsonl"
    # 5 resolved-expected with outcome=resolved
    for i in 1 2 3 4 5; do
        printf '{"schema_version":2,"timestamp":"2099-01-01T00:0%s:00Z","outcome":"resolved","expected_outcome":"resolved","stage":"parse","confidence":0.92}\n' "$i" >> "$AFILE"
    done
    # 1 resolved-expected with outcome=escalated (false escalation)
    printf '{"schema_version":2,"timestamp":"2099-01-01T00:06:00Z","outcome":"escalated","expected_outcome":"resolved","stage":"escalate","confidence":0.3}\n' >> "$AFILE"
    # 3 escalated-expected with outcome=escalated (designed escalations — must NOT count)
    for i in 7 8 9; do
        printf '{"schema_version":2,"timestamp":"2099-01-01T00:0%s:00Z","outcome":"escalated","expected_outcome":"escalated","stage":"escalate","confidence":0.1}\n' "$i" >> "$AFILE"
    done
    # 2 noop-expected events (must NOT count)
    for i in 1 2; do
        printf '{"schema_version":2,"timestamp":"2099-01-01T00:1%s:00Z","outcome":"resolved","expected_outcome":"noop","stage":"parse","confidence":0.5}\n' "$i" >> "$AFILE"
    done
    # Rate should be 1/6 = 0.1667 (> 0.15 → FAIL) but without refinement it
    # would be 4/9 = 0.44 (designed escalations inflate it).
    # Refined formula: escalated WHERE expected==resolved / total WHERE expected==resolved
    # = 1 / 6 = 0.1667 → exits 1 (above threshold 0.15)
    run "$MEASURE" --audit-dir "$AUDIT" --since 1h --max-false-escalate 0.15 --verbose
    # The rate is 1/6 ≈ 0.1667; must be > 0.15
    [ "$status" -eq 1 ]
    [[ "$output" =~ "rate=" ]]
    # Without refined formula (old: escalated/total), designed escalations
    # would give 4/9=0.44 — the test verifies the formula uses expected_outcome filter
    # by checking the counts in output match resolved-expected denominator (6 not 9)
    [[ "$output" =~ "resolved=5" ]]
    [[ "$output" =~ "escalated=1" ]]
}

# T13: measure excludes blocked_decision_cooldown from both numerator and denominator
@test "T13 measure_refined_formula: excludes blocked_decision_cooldown" {
    MEASURE="$BATS_TEST_DIRNAME/../measure-orchestrator-soak.sh"
    AUDIT="$TMPROOT/measure-cooldown-fixture"
    mkdir -p "$AUDIT"
    AFILE="$AUDIT/audit-2099-02-01.jsonl"
    # 4 clean resolved-expected resolved
    for i in 1 2 3 4; do
        printf '{"schema_version":2,"timestamp":"2099-02-01T00:0%s:00Z","outcome":"resolved","expected_outcome":"resolved","stage":"parse","confidence":0.9}\n' "$i" >> "$AFILE"
    done
    # 1 blocked_decision_cooldown — must be excluded from denominator
    printf '{"schema_version":2,"timestamp":"2099-02-01T00:05:00Z","outcome":"blocked_decision_cooldown","expected_outcome":"resolved","stage":"resolve","confidence":0.9}\n' >> "$AFILE"
    # Rate without exclusion: 0/5 = 0.0 (pass); with exclusion: 0/4 = 0.0 (pass)
    # We care that blocked events don't inflate denominator — verify count in output
    run "$MEASURE" --audit-dir "$AUDIT" --since 1h --max-false-escalate 0.15 --verbose
    [ "$status" -eq 0 ]
    [[ "$output" =~ "resolved=4" ]]
    [[ "$output" =~ "escalated=0" ]]
}

# T14: measure backward-compat: events without expected_outcome field are ignored
@test "T14 measure_backward_compat: events without expected_outcome are excluded" {
    MEASURE="$BATS_TEST_DIRNAME/../measure-orchestrator-soak.sh"
    AUDIT="$TMPROOT/measure-compat-fixture"
    mkdir -p "$AUDIT"
    AFILE="$AUDIT/audit-2099-03-01.jsonl"
    # Old events without expected_outcome field — should be ignored in refined metric
    for i in 1 2 3; do
        printf '{"schema_version":2,"timestamp":"2099-03-01T00:0%s:00Z","outcome":"resolved","stage":"parse","confidence":0.9}\n' "$i" >> "$AFILE"
    done
    for i in 4 5; do
        printf '{"schema_version":2,"timestamp":"2099-03-01T00:0%s:00Z","outcome":"escalated","stage":"escalate","confidence":0.3}\n' "$i" >> "$AFILE"
    done
    # No expected_outcome=resolved events → should exit 1 (no data for refined metric)
    run "$MEASURE" --audit-dir "$AUDIT" --since 1h --max-false-escalate 0.15 --verbose
    [ "$status" -eq 1 ]
}
