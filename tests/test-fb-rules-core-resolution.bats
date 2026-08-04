#!/usr/bin/env bats
# test-fb-rules-core-resolution.bats — core-only fb-rules resolution regression.
# The one-cycle deprecation copy (plugins/dr-orchestrate/rules/fb-rules.yaml)
# and the plugin-local fallback in the shims were removed after consumers
# resynced to the core path. This suite pins the post-removal contract:
#   - The plugin copy stays deleted (regression guard against re-introduction).
#   - The shims resolve ONLY core paths (runtime install first, repo-relative
#     core second) and honour an explicit DR_ORCH_FB_RULES override.
#   - The floor/map accessors keep working through the core loader.

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export PLUGIN_ROOT="$REPO_ROOT/plugins/dr-orchestrate"
  export DATARIM_RUNTIME="$REPO_ROOT"
  unset DR_AUTONOMY_RULES
}

# ── Deprecation copy is gone ─────────────────────────────────────────────────

@test "deprecation copy no longer exists at the old plugin path" {
  [ ! -e "$PLUGIN_ROOT/rules/fb-rules.yaml" ]
}

@test "no shipped script references the old plugin fb-rules path" {
  run grep -rn 'plugins/dr-orchestrate/rules/fb-rules\.yaml' \
    "$PLUGIN_ROOT/scripts" "$REPO_ROOT/dev-tools" "$REPO_ROOT/scripts" \
    "$REPO_ROOT/cli"
  [ "$status" -ne 0 ]
}

# ── Prefer-core in rules_loader.sh ──────────────────────────────────────────

@test "rules_loader picks runtime core path when DATARIM_RUNTIME carries it" {
  run bash -c "
    export DATARIM_RUNTIME='$REPO_ROOT'
    unset DR_ORCH_FB_RULES DR_AUTONOMY_RULES
    source '$PLUGIN_ROOT/scripts/rules_loader.sh'
    echo \"\$DR_ORCH_FB_RULES\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"dev-tools/rules/fb-rules.yaml"* ]]
  [[ "$output" != *"plugins/dr-orchestrate/rules"* ]]
}

@test "rules_loader resolves repo-relative CORE path when runtime lacks the file" {
  local tmp_runtime
  tmp_runtime="$(mktemp -d)"
  # tmp_runtime has no dev-tools/rules/fb-rules.yaml → the repo-relative
  # CORE path wins. There is no plugin-local copy to fall back to anymore.
  run bash -c "
    export DATARIM_RUNTIME='$tmp_runtime'
    unset DR_ORCH_FB_RULES DR_AUTONOMY_RULES
    source '$PLUGIN_ROOT/scripts/rules_loader.sh'
    echo \"\$DR_ORCH_FB_RULES\"
  "
  rm -rf "$tmp_runtime"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dev-tools/rules/fb-rules.yaml"* ]]
  [[ "$output" != *"plugins/dr-orchestrate/rules"* ]]
}

@test "load_always_gated_floor resolves the floor from the core canonical" {
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

# ── action_gate.sh core-only resolution ──────────────────────────────────────

@test "action_gate.sh prefers runtime core path when DATARIM_RUNTIME is set" {
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

@test "action_gate.sh resolves repo-relative CORE path when runtime lacks the file" {
  local tmpdir tmp_runtime spaces_dir audit_file
  tmpdir="$(mktemp -d)"
  tmp_runtime="$tmpdir/nocore"
  spaces_dir="$tmpdir/spaces"
  audit_file="$tmpdir/audit.jsonl"
  mkdir -p "$spaces_dir/arcanada" "$tmp_runtime"
  cat > "$spaces_dir/arcanada/space.yml" <<'YAML'
space:
  name: arcanada
autonomy:
  schema_version: 1
  policy:
    merge_main: auto
YAML
  run env DATARIM_RUNTIME="$tmp_runtime" \
      DATARIM_SPACES_ROOT="$spaces_dir" \
      DATARIM_ACTIVE_SPACE=arcanada \
      DR_ORCH_AUTONOMY_AUDIT="$audit_file" \
      DR_AUTONOMY_AUDIT="$audit_file" \
      "$PLUGIN_ROOT/scripts/action_gate.sh" gate --action merge_main
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
}
