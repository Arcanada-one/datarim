#!/usr/bin/env bats
# test_rule_first_resolution.bats — over-escalation root-cause regression.
#
# Defect class: resolve_and_route (cmd_run.sh unknown-prompt handler) used to
# go straight to the LLM subagent chain without consulting the deterministic
# rule set. On any host where the chain is absent, unauthenticated, or
# under-confident, the escalate branch is the guaranteed destination — so
# rule-resolvable input (prose-wrapped slash commands, commands not yet in the
# classifier's closed set) false-escalated on every cycle and the soak
# false-escalate verdict gate failed far above its threshold.
#
# Fix under test: rule-first fast path — a trusted-rule hit at/above the
# confidence threshold resolves locally (backend_used=rule) with zero LLM
# involvement; only a rule miss or sub-threshold hit reaches the chain.
#
# T1  non-slash rule-matching prompt resolves via rule-first, no backends
# T2  synthetic reference corpus: false-escalate rate 0 with backends absent
#     (pre-fix mechanism: every resolvable prompt escalates → rate 1.0)
# T3  non-matching prompt still escalates (no over-resolution regression)
# T4  sub-threshold rule hit falls through to the chain (threshold respected)

setup() {
  export PLUGIN_ROOT
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_ROOT
  REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"

  export AUDIT_DIR="$BATS_TEST_TMPDIR/audit"
  export DR_ORCH_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export DR_ORCH_ACTION_EXECUTOR_LOG="$BATS_TEST_TMPDIR/actions.log"
  # Hermetic rules: bundled defaults only — no operator user.yaml leakage.
  export DR_ORCH_RULES_USER="$BATS_TEST_TMPDIR/no-user-rules.yaml"
  # Backend chain resolves to a binary that does not exist on any host.
  export DR_ORCH_SUBAGENT_CHAIN="mock-absent"
  export DR_ORCH_RESOLVER_TIMEOUT_S=2

  # action_gate fixture: permissive space so framework_command executes.
  export DATARIM_SPACES_ROOT="$BATS_TEST_TMPDIR/spaces"
  export DATARIM_ACTIVE_SPACE=arcanada
  export DR_AUTONOMY_RULES="$BATS_TEST_TMPDIR/fb-rules.yaml"
  export DR_ORCH_AUTONOMY_AUDIT="$BATS_TEST_TMPDIR/autonomy.jsonl"
  mkdir -p "$DATARIM_SPACES_ROOT/arcanada" "$AUDIT_DIR"
  # audit_sink refuses group/other-writable audit parents; the default
  # umask on some CI hosts creates 775 directories.
  chmod 700 "$AUDIT_DIR"
  cat > "$DATARIM_SPACES_ROOT/arcanada/space.yml" <<'YAML'
space:
  name: arcanada
autonomy:
  schema_version: 1
  policy:
    cross_project_write: auto
YAML
  cat > "$DR_AUTONOMY_RULES" <<'YAML'
always_gated_floor: [finance_action]
action_autonomy_map:
  framework_command: cross_project_write
YAML
}

audit_file() {
  echo "$AUDIT_DIR/audit-$(date -u +%Y-%m-%d).jsonl"
}

@test "T1 rule-first: prose-wrapped slash command resolves without any LLM backend" {
  run env DR_ORCH_EXPECTED_OUTCOME=resolved \
    "$PLUGIN_ROOT/scripts/cmd_run.sh" --unknown-prompt "please run /dr-status"
  [ "$status" -eq 0 ]
  [[ "$output" == *"backend=rule"* ]]
  [[ "$output" == *"action=/dr-status"* ]]
  grep -qx "/dr-status" "$DR_ORCH_ACTION_EXECUTOR_LOG"
  evt="$(tail -1 "$(audit_file)")"
  [ "$(jq -r '.outcome' <<<"$evt")" = "resolved" ]
  [ "$(jq -r '.reason' <<<"$evt")" = "rule_first_hit" ]
  [ "$(jq -r '.backend_used' <<<"$evt")" = "rule" ]
  [ "$(jq -r '.expected_outcome' <<<"$evt")" = "resolved" ]
}

@test "T2 synthetic reference corpus: false-escalate rate 0.0000 with backends absent" {
  # Resolvable bucket — mirrors the soak driver's RESOLVED_PROMPTS corpus
  # (PRD-canonical traffic-mix spec). Distinct panes dodge the per-pane
  # 60 s decision cooldown so every resolution lands in the metric.
  resolvable=(
    "/dr-status" "/dr-help" "/dr-init" "/dr-prd" "/dr-plan" "/dr-do"
    "/dr-qa" "/dr-archive" "/dr-continue" "/dr-design" "/dr-compliance"
    "please run /dr-status" "run /dr-help now" "/dr-do please"
  )
  i=0
  for p in "${resolvable[@]}"; do
    i=$((i + 1))
    env DR_ORCH_EXPECTED_OUTCOME=resolved \
      "$PLUGIN_ROOT/scripts/cmd_run.sh" --unknown-prompt "$p" --pane "res:$i" \
      >/dev/null
  done
  # Designed-escalation bucket (ASCII subset of the driver's corpus).
  unresolvable=("hello world" "random text foo bar" "tell me a joke" "abc")
  i=0
  for p in "${unresolvable[@]}"; do
    i=$((i + 1))
    env DR_ORCH_EXPECTED_OUTCOME=escalated \
      "$PLUGIN_ROOT/scripts/cmd_run.sh" --unknown-prompt "$p" --pane "esc:$i" \
      >/dev/null
  done

  run "$REPO_ROOT/dev-tools/measure-orchestrator-soak.sh" \
    --audit-dir "$AUDIT_DIR" --since 1h --max-false-escalate 0.15 --verbose
  echo "measure: $output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"resolved=14 escalated=0"* ]]
  [[ "$output" == *"rate=0.0000"* ]]
}

@test "T3 non-matching prompt still escalates (no over-resolution)" {
  run env DR_ORCH_EXPECTED_OUTCOME=escalated \
    "$PLUGIN_ROOT/scripts/cmd_run.sh" --unknown-prompt "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dr-orchestrate: escalate"* ]]
  evt="$(tail -1 "$(audit_file)")"
  [ "$(jq -r '.outcome' <<<"$evt")" = "escalated" ]
}

@test "T4 sub-threshold rule hit falls through to the chain (and escalates here)" {
  # /dr-status carries confidence 0.90 in the bundled rules; raising the
  # runtime threshold above it must bypass the rule-first path.
  run env DR_ORCH_CONFIDENCE_THRESHOLD=0.99 DR_ORCH_EXPECTED_OUTCOME=resolved \
    "$PLUGIN_ROOT/scripts/cmd_run.sh" --unknown-prompt "/dr-status"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dr-orchestrate: escalate"* ]]
  [[ "$output" != *"backend=rule"* ]]
}
