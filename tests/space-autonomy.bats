#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SPACES_ROOT="$BATS_TEST_TMPDIR/spaces"
  export RULES_FILE="$BATS_TEST_TMPDIR/fb-rules.yaml"
  export DR_AUTONOMY_AUDIT="$BATS_TEST_TMPDIR/autonomy.jsonl"
  export DATARIM_TASK_ID="TUNE-0436"
  export DR_AUTONOMY_ACTOR="bats-agent"
  mkdir -p "$SPACES_ROOT/arcanada" "$SPACES_ROOT/aether"
  mkdir -p "$BATS_TEST_TMPDIR/escape"

  cat > "$SPACES_ROOT/arcanada/space.yml" <<'YAML'
space:
  name: arcanada
  status: active
autonomy:
  schema_version: 1
  policy:
    feature_branch_push: auto
    merge_main: auto
    prod_deploy: auto
    publish_public: auto
    secret_rotation: auto
    verify: auto
    cross_project_write: auto
YAML

  cat > "$SPACES_ROOT/aether/space.yml" <<'YAML'
space:
  name: aether
  status: active
autonomy:
  schema_version: 1
  policy:
    feature_branch_push: auto
    merge_main: operator
    prod_deploy: operator
    publish_public: operator
    secret_rotation: operator
    verify: auto
    cross_project_write: operator
YAML

  cat > "$BATS_TEST_TMPDIR/escape/space.yml" <<'YAML'
space:
  name: escape
autonomy:
  schema_version: 1
  policy:
    merge_main: auto
YAML

  cat > "$RULES_FILE" <<'YAML'
always_gated_floor:
  - finance_action
  - legal_action
  - git_history_delete
  - force_push_drops_commits
  - irreversible_db_no_backup
action_autonomy_map:
  feature_branch_push: feature_branch_push
  merge_main: merge_main
  prod_deploy: prod_deploy
  publish_public: publish_public
  secret_rotation: secret_rotation
  verify: verify
  cross_project_write: cross_project_write
  public_package_release: publish_public
  force_push: merge_main
  irreversible_db_op: prod_deploy
YAML
}

gate() {
  local payload='{}'
  if [[ $# -ge 3 ]]; then
    payload="$3"
  fi
  run env \
    DATARIM_SPACES_ROOT="$SPACES_ROOT" \
    DATARIM_ACTIVE_SPACE="$1" \
    DR_AUTONOMY_RULES="$RULES_FILE" \
    "$REPO_ROOT/dev-tools/resolve-space-autonomy.sh" gate \
      --action "$2" --payload "$payload"
}

@test "Arcanada merge_main resolves auto" {
  gate arcanada merge_main
  [ "$status" -eq 0 ] && [ "$(jq -r '.decision' <<<"$output")" = auto ]
}

@test "Aether merge_main remains operator-gated" {
  gate aether merge_main
  [ "$status" -eq 10 ] && [ "$(jq -r '.decision' <<<"$output")" = operator ]
}

@test "feature branch push is explicitly auto in both existing spaces" {
  gate arcanada feature_branch_push
  [ "$status" -eq 0 ]
  gate aether feature_branch_push
  [ "$status" -eq 0 ]
}

@test "finance floor overrides Arcanada auto policy" {
  gate arcanada finance_action
  [ "$status" -eq 10 ] \
    && [ "$(jq -r '.floor_hit' <<<"$output")" = true ] \
    && [ "$(jq -r '.precedence_layer' <<<"$output")" = P0 ] \
    && [ "$(jq -r '.space' <<<"$output")" = arcanada ]
}

@test "commit-dropping force push is always gated" {
  gate arcanada force_push '{"drops_commits":true}'
  [ "$status" -eq 10 ] \
    && [ "$(jq -r '.effective_action_kind' <<<"$output")" = force_push_drops_commits ]
}

@test "non-dropping main update follows merge_main policy" {
  gate arcanada force_push '{"drops_commits":false,"target_branch":"main"}'
  [ "$status" -eq 0 ]
  gate aether force_push '{"drops_commits":false,"target_branch":"main"}'
  [ "$status" -eq 10 ]
}

@test "non-dropping feature force push follows feature branch policy" {
  gate aether force_push '{"drops_commits":false,"target_branch":"feat/safe-rewrite"}'
  [ "$status" -eq 0 ] \
    && [ "$(jq -r '.effective_action_kind' <<<"$output")" = feature_branch_push ]
}

@test "irreversible DB operation without backup is always gated" {
  gate arcanada irreversible_db_op '{"backup_verified":false}'
  [ "$status" -eq 10 ] \
    && [ "$(jq -r '.effective_action_kind' <<<"$output")" = irreversible_db_no_backup ]
}

@test "DB operation with verified backup follows space policy" {
  gate arcanada irreversible_db_op '{"backup_verified":true}'
  [ "$status" -eq 0 ]
  gate aether irreversible_db_op '{"backup_verified":true}'
  [ "$status" -eq 10 ]
}

@test "missing autonomy block fails safe to operator" {
  yq -i 'del(.autonomy)' "$SPACES_ROOT/arcanada/space.yml"
  gate arcanada merge_main
  [ "$status" -eq 10 ] \
    && [ "$(jq -r '.reason_code' <<<"$output")" = invalid_or_missing_autonomy ]
}

@test "one malformed policy value invalidates the whole block" {
  yq -i '.autonomy.policy.secret_rotation = "yes"' "$SPACES_ROOT/arcanada/space.yml"
  gate arcanada merge_main
  [ "$status" -eq 10 ] \
    && [ "$(jq -r '.reason_code' <<<"$output")" = invalid_or_missing_autonomy ]
}

@test "unresolved space fails safe to operator" {
  gate missing merge_main
  [ "$status" -eq 10 ] \
    && [ "$(jq -r '.reason_code' <<<"$output")" = unresolved_space ]
}

@test "missing immutable floor is an invariant error" {
  yq -i 'del(.always_gated_floor)' "$RULES_FILE"
  gate arcanada merge_main
  [ "$status" -eq 2 ] \
    && [ "$(jq -r '.reason_code' <<<"$output")" = invalid_rules ]
}

@test "unknown action kind fails safe to operator" {
  gate arcanada unknown_action
  [ "$status" -eq 10 ] \
    && [ "$(jq -r '.reason_code' <<<"$output")" = unmapped_action ]
}

@test "patch package release requires both release carve-out and space publish policy" {
  gate arcanada public_package_release \
    '{"bump_level":"patch","escalate":false,"zero_x_breaking":false}'
  [ "$status" -eq 0 ]
  gate aether public_package_release \
    '{"bump_level":"patch","escalate":false,"zero_x_breaking":false}'
  [ "$status" -eq 10 ]
}

@test "major package release remains operator-gated in Arcanada" {
  gate arcanada public_package_release \
    '{"bump_level":"major","escalate":false,"zero_x_breaking":false}'
  [ "$status" -eq 10 ] \
    && [ "$(jq -r '.reason_code' <<<"$output")" = release_carveout_denied ] \
    && [ "$(jq -r '.precedence_layer' <<<"$output")" = P1 ]
}

@test "0.x breaking package release remains operator-gated" {
  gate arcanada public_package_release \
    '{"bump_level":"minor","escalate":false,"zero_x_breaking":true}'
  [ "$status" -eq 10 ] \
    && [ "$(jq -r '.reason_code' <<<"$output")" = release_carveout_denied ]
}

@test "core resolver writes the decision audit before returning" {
  gate arcanada merge_main
  [ "$status" -eq 0 ] \
    && [ -s "$DR_AUTONOMY_AUDIT" ] \
    && [ "$(tail -1 "$DR_AUTONOMY_AUDIT" | jq -r '.decision')" = auto ] \
    && [ "$(tail -1 "$DR_AUTONOMY_AUDIT" | jq -r '.timestamp | length > 0')" = true ] \
    && [ "$(tail -1 "$DR_AUTONOMY_AUDIT" | jq -r '.actor')" = bats-agent ] \
    && [ "$(tail -1 "$DR_AUTONOMY_AUDIT" | jq -r '.task_id')" = TUNE-0436 ]
}

@test "active space name rejects path traversal" {
  gate '../escape' merge_main
  [ "$status" -eq 10 ] \
    && [ "$(jq -r '.reason_code' <<<"$output")" = unresolved_space ]
}

@test "force push without an explicit no-loss discriminator fails safe" {
  gate arcanada force_push '{}'
  [ "$status" -eq 10 ] \
    && [ "$(jq -r '.effective_action_kind' <<<"$output")" = force_push_drops_commits ]
}

@test "non-dropping force push without a target branch fails safe" {
  gate arcanada force_push '{"drops_commits":false}'
  [ "$status" -eq 10 ] \
    && [ "$(jq -r '.reason_code' <<<"$output")" = unmapped_action ]
}

@test "dr-auto marker space field resolves the active space" {
  mkdir -p "$BATS_TEST_TMPDIR/work/datarim"
  cat > "$BATS_TEST_TMPDIR/work/datarim/.auto-mode-active" <<'YAML'
task_id: TUNE-0436
space: arcanada
YAML
  run bash -c "cd '$BATS_TEST_TMPDIR/work' && \
    DATARIM_SPACES_ROOT='$SPACES_ROOT' \
    DR_AUTONOMY_RULES='$RULES_FILE' \
    DR_AUTONOMY_AUDIT='$DR_AUTONOMY_AUDIT' \
    '$REPO_ROOT/dev-tools/resolve-space-autonomy.sh' gate --action merge_main"
  [ "$status" -eq 0 ] \
    && [ "$(jq -r '.space' <<<"$output")" = arcanada ]
}
