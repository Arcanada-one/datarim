#!/usr/bin/env bats
# test-fb-policy-core-resolution.bats — TUNE-0449 Phase 5.1 regression.
# Verifies that the hard-gated floor and the autonomy map resolve from the
# core path (dev-tools/rules/fb-rules.yaml) with no DR_AUTONOMY_RULES set
# and with the dr-orchestrate plugin absent.
#
# V-AC covered: V-AC-2a (core path exists), V-AC-2b (fail-functional default).

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # Point DATARIM_RUNTIME at the repo root so the default path resolves.
  export DATARIM_RUNTIME="$REPO_ROOT"
  # Ensure no DR_AUTONOMY_RULES override is active.
  unset DR_AUTONOMY_RULES
  # Provide a minimal spaces root so policy decisions can resolve.
  export DATARIM_SPACES_ROOT="$BATS_TEST_TMPDIR/spaces"
  mkdir -p "$DATARIM_SPACES_ROOT/arcanada"
  cat > "$DATARIM_SPACES_ROOT/arcanada/space.yml" <<'YAML'
space:
  name: arcanada
autonomy:
  schema_version: 1
  policy:
    feature_branch_push: auto
    merge_main: auto
    prod_deploy: operator
    publish_public: operator
    secret_rotation: operator
    verify: auto
    cross_project_write: auto
YAML
  export DATARIM_ACTIVE_SPACE=arcanada
  export DR_AUTONOMY_AUDIT="$BATS_TEST_TMPDIR/autonomy.jsonl"
}

# ── Core path presence ──────────────────────────────────────────────────────

@test "V-AC-2a: core fb-rules.yaml exists at dev-tools/rules/fb-rules.yaml" {
  [ -f "$REPO_ROOT/dev-tools/rules/fb-rules.yaml" ]
}

@test "fb-policy-loader.sh is executable" {
  [ -x "$REPO_ROOT/dev-tools/fb-policy-loader.sh" ]
}

# ── Fail-functional default (floor loads from core, no plugin) ──────────────

@test "load_always_gated_floor succeeds from core with no DR_AUTONOMY_RULES" {
  run bash "$REPO_ROOT/dev-tools/fb-policy-loader.sh" load_always_gated_floor
  [ "$status" -eq 0 ]
  # Must contain force_push_drops_commits — the canonical immutable floor entry.
  echo "$output" | jq -e 'index("force_push_drops_commits") != null'
}

@test "load_action_autonomy_map succeeds from core with no DR_AUTONOMY_RULES" {
  run bash "$REPO_ROOT/dev-tools/fb-policy-loader.sh" load_action_autonomy_map
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("feature_branch_push")'
}

@test "load_fb_policy returns non-empty array from core" {
  run bash "$REPO_ROOT/dev-tools/fb-policy-loader.sh" load_fb_policy
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq 'length')
  [ "$count" -ge 8 ]
}

@test "load_fb_hard_gates returns non-empty array from core" {
  run bash "$REPO_ROOT/dev-tools/fb-policy-loader.sh" load_fb_hard_gates
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'index("force_push_main") != null'
}

# ── Resolver uses core path when DR_AUTONOMY_RULES is unset ─────────────────

@test "_autonomy_rules returns the core fb-rules.yaml path when DR_AUTONOMY_RULES unset" {
  run bash -c "
    source '$REPO_ROOT/dev-tools/lib/space-autonomy.sh'
    _autonomy_rules
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"dev-tools/rules/fb-rules.yaml"* ]]
}

@test "floor resolves via autonomy_decision (force_push drops_commits -> exit 10, floor_hit true)" {
  # Source lib/space-autonomy.sh directly (the wrapper script parses its own
  # argv at script level and would call usage+exit if sourced with no args).
  run bash -c "
    export DATARIM_RUNTIME='$REPO_ROOT'
    export DATARIM_SPACES_ROOT='$DATARIM_SPACES_ROOT'
    export DATARIM_ACTIVE_SPACE=arcanada
    source '$REPO_ROOT/dev-tools/lib/space-autonomy.sh'
    autonomy_decision force_push '{\"drops_commits\":true}'
  "
  [ "$status" -eq 10 ]
  echo "$output" | jq -e '.floor_hit == true'
  echo "$output" | jq -e '.reason_code == "always_gated_floor"'
}

@test "feature_branch_push resolves auto from core map (no plugin)" {
  run bash -c "
    export DATARIM_RUNTIME='$REPO_ROOT'
    export DATARIM_SPACES_ROOT='$DATARIM_SPACES_ROOT'
    export DATARIM_ACTIVE_SPACE=arcanada
    source '$REPO_ROOT/dev-tools/lib/space-autonomy.sh'
    autonomy_decision feature_branch_push '{}'
  "
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "auto"'
  echo "$output" | jq -e '.floor_hit == false'
}

# ── Fail-closed on missing file ──────────────────────────────────────────────

@test "load_always_gated_floor exits 2 when file is absent" {
  run bash "$REPO_ROOT/dev-tools/fb-policy-loader.sh" load_always_gated_floor \
    /nonexistent/path/fb-rules.yaml
  [ "$status" -eq 2 ]
}

@test "load_fb_policy returns [] when file is absent (fail-open)" {
  run bash "$REPO_ROOT/dev-tools/fb-policy-loader.sh" load_fb_policy \
    /nonexistent/path/fb-rules.yaml
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

# ── Stack-agnostic (transport terms must not appear in core files) ───────────

@test "fb-rules.yaml contains no tmux, HMAC, Redis, or webhook terms" {
  run grep -iE 'tmux|HMAC|Redis|webhook' \
    "$REPO_ROOT/dev-tools/rules/fb-rules.yaml"
  [ "$status" -eq 1 ]
}

@test "fb-policy-loader.sh contains no tmux, HMAC, Redis, or webhook terms" {
  run grep -iE 'tmux|HMAC|Redis|webhook' \
    "$REPO_ROOT/dev-tools/fb-policy-loader.sh"
  [ "$status" -eq 1 ]
}
