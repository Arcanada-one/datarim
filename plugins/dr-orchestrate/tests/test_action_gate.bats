#!/usr/bin/env bats

setup() {
  export PLUGIN_ROOT
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_ROOT
  REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
  export DATARIM_SPACES_ROOT="$BATS_TEST_TMPDIR/spaces"
  export DR_AUTONOMY_RULES="$BATS_TEST_TMPDIR/fb-rules.yaml"
  export DR_ORCH_AUTONOMY_AUDIT="$BATS_TEST_TMPDIR/autonomy.jsonl"
  mkdir -p "$DATARIM_SPACES_ROOT/arcanada"
  cat > "$DATARIM_SPACES_ROOT/arcanada/space.yml" <<'YAML'
space:
  name: arcanada
autonomy:
  schema_version: 1
  policy:
    merge_main: auto
YAML
  cat > "$DR_AUTONOMY_RULES" <<'YAML'
always_gated_floor: [finance_action]
action_autonomy_map:
  merge_main: merge_main
YAML
}

@test "action gate allows configured automatic action and writes audit first" {
  run env DATARIM_ACTIVE_SPACE=arcanada \
    "$PLUGIN_ROOT/scripts/action_gate.sh" gate --action merge_main
  [ "$status" -eq 0 ] \
    && [ -s "$DR_ORCH_AUTONOMY_AUDIT" ] \
    && [ "$(jq -r '.decision' "$DR_ORCH_AUTONOMY_AUDIT")" = auto ]
}

@test "action gate blocks floor action even in permissive space" {
  run env DATARIM_ACTIVE_SPACE=arcanada \
    "$PLUGIN_ROOT/scripts/action_gate.sh" gate --action finance_action
  [ "$status" -eq 10 ] \
    && [ "$(jq -r '.floor_hit' "$DR_ORCH_AUTONOMY_AUDIT")" = true ]
}

@test "action gate fails safe when active space is unresolved" {
  run env DATARIM_ACTIVE_SPACE=missing \
    "$PLUGIN_ROOT/scripts/action_gate.sh" gate --action merge_main
  [ "$status" -eq 10 ] \
    && [ "$(jq -r '.reason_code' "$DR_ORCH_AUTONOMY_AUDIT")" = unresolved_space ]
}

@test "cmd_run wires action_kind through action_gate before autonomous resolution" {
  grep -qF 'action_kind="$(printf' "$PLUGIN_ROOT/scripts/cmd_run.sh" \
    && grep -qF 'scripts/action_gate.sh" gate' "$PLUGIN_ROOT/scripts/cmd_run.sh" \
    && grep -qF 'escalated_space_policy' "$PLUGIN_ROOT/scripts/cmd_run.sh"
}

@test "action gate defaults to the bundled policy file" {
  unset DR_AUTONOMY_RULES
  run env DATARIM_ACTIVE_SPACE=arcanada \
    "$PLUGIN_ROOT/scripts/action_gate.sh" gate --action merge_main
  [ "$status" -eq 0 ]
}
