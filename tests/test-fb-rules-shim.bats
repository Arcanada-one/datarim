#!/usr/bin/env bats
# test-fb-rules-shim.bats — prefer-core fb-rules resolution regression.
# The one-minor-cycle deprecation shim (a plugin-local copy of fb-rules.yaml at
# plugins/dr-orchestrate/rules/fb-rules.yaml, with fallback branches in
# rules_loader.sh / action_gate.sh) has been removed. The loaders now read the
# single core canonical dev-tools/rules/fb-rules.yaml, honouring only an
# explicit caller override (DR_ORCH_FB_RULES / DR_AUTONOMY_RULES). These tests
# lock that contract:
#   - rules_loader resolves the core path when DATARIM_RUNTIME is set.
#   - an explicit DR_ORCH_FB_RULES override still wins.
#   - load_always_gated_floor reads the core floor.
#   - action_gate.sh resolves the core path.

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export PLUGIN_ROOT="$REPO_ROOT/plugins/dr-orchestrate"
  export DATARIM_RUNTIME="$REPO_ROOT"
  unset DR_AUTONOMY_RULES
}

# ── Prefer-core in rules_loader.sh ──────────────────────────────────────────

@test "rules_loader picks core path when DATARIM_RUNTIME is set and core exists" {
  # With DATARIM_RUNTIME pointing at the repo, the loader resolves the core file.
  run bash -c "
    export DATARIM_RUNTIME='$REPO_ROOT'
    unset DR_ORCH_FB_RULES DR_AUTONOMY_RULES
    source '$PLUGIN_ROOT/scripts/rules_loader.sh'
    echo \"\$DR_ORCH_FB_RULES\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"dev-tools/rules/fb-rules.yaml"* ]]
}

@test "load_always_gated_floor resolves force_push_drops_commits from the core fb-rules" {
  export DR_ORCH_FB_RULES="$REPO_ROOT/dev-tools/rules/fb-rules.yaml"
  run bash "$PLUGIN_ROOT/scripts/rules_loader.sh" load_always_gated_floor
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'index("force_push_drops_commits") != null'
}

# ── Explicit-override still respected ────────────────────────────────────────

@test "DR_ORCH_FB_RULES explicit override wins over core detection" {
  local tmp_rules
  tmp_rules="$(mktemp)"
  cat > "$tmp_rules" <<'YAML'
always_gated_floor: [test_sentinel_action]
action_autonomy_map:
  test_sentinel_action: test_sentinel_action
YAML
  run bash -c "
    export DATARIM_RUNTIME='$REPO_ROOT'
    export DR_ORCH_FB_RULES='$tmp_rules'
    bash '$PLUGIN_ROOT/scripts/rules_loader.sh' load_always_gated_floor
  "
  rm -f "$tmp_rules"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'index("test_sentinel_action") != null'
}

# ── action_gate.sh prefers core ──────────────────────────────────────────────

@test "action_gate.sh prefers core path when DATARIM_RUNTIME is set" {
  local tmpdir spaces_dir audit_file
  tmpdir="$(mktemp -d)"
  spaces_dir="$tmpdir/spaces"
  audit_file="$tmpdir/audit.jsonl"
  mkdir -p "$spaces_dir/arcanada"
  cat > "$spaces_dir/arcanada/space.yml" <<'YAML'
space:
  name: arcanada
autonomy:
  schema_version: 1
  policy:
    merge_main: auto
YAML
  run env DATARIM_RUNTIME="$REPO_ROOT" \
      DATARIM_SPACES_ROOT="$spaces_dir" \
      DATARIM_ACTIVE_SPACE=arcanada \
      DR_ORCH_AUTONOMY_AUDIT="$audit_file" \
      DR_AUTONOMY_AUDIT="$audit_file" \
      "$PLUGIN_ROOT/scripts/action_gate.sh" gate --action merge_main
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
}
