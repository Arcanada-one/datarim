#!/usr/bin/env bats
# test-fb-rules-shim.bats — TUNE-0449 Phase 5.2 regression.
# Verifies the deprecation-window shim contract:
#   - The old plugin path still resolves the floor when the core path wins.
#   - When both exist, the core path wins (loader prefers core).
#   - When only the plugin copy exists (copy-mode / mid-migration), it still resolves.
#
# V-AC covered: V-AC-2b (deprecation shim + prefer-core).

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export PLUGIN_ROOT="$REPO_ROOT/plugins/dr-orchestrate"
  export DATARIM_RUNTIME="$REPO_ROOT"
  unset DR_AUTONOMY_RULES
}

# ── Shim file presence ───────────────────────────────────────────────────────

@test "deprecation shim exists at old plugin path" {
  [ -f "$PLUGIN_ROOT/rules/fb-rules.yaml" ]
}

@test "shim contains always_gated_floor (data is intact)" {
  run grep -c 'always_gated_floor' "$PLUGIN_ROOT/rules/fb-rules.yaml"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
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

@test "rules_loader falls back to plugin copy when core path is absent" {
  local tmp_runtime
  tmp_runtime="$(mktemp -d)"
  # tmp_runtime has no dev-tools/rules/fb-rules.yaml → shim triggers.
  run bash -c "
    export DATARIM_RUNTIME='$tmp_runtime'
    unset DR_ORCH_FB_RULES DR_AUTONOMY_RULES
    source '$PLUGIN_ROOT/scripts/rules_loader.sh'
    echo \"\$DR_ORCH_FB_RULES\"
  "
  rm -rf "$tmp_runtime"
  [ "$status" -eq 0 ]
  [[ "$output" == *"plugins/dr-orchestrate/rules/fb-rules.yaml"* ]]
}

@test "load_always_gated_floor resolves from old plugin path when DR_ORCH_FB_RULES set to it" {
  export DR_ORCH_FB_RULES="$PLUGIN_ROOT/rules/fb-rules.yaml"
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

@test "action_gate.sh falls back to plugin copy when core is absent" {
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
