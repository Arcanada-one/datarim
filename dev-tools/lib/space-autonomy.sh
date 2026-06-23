#!/usr/bin/env bash
# shellcheck shell=bash
# Core fail-closed resolver for per-space operational autonomy.

_autonomy_json() {
  jq -n -c "$@"
}

_autonomy_spaces_root() {
  if [[ -n "${DATARIM_SPACES_ROOT:-}" ]]; then
    printf '%s\n' "$DATARIM_SPACES_ROOT"
    return 0
  fi
  if [[ -n "${DATARIM_WORKSPACE_ROOT:-}" && -d "$DATARIM_WORKSPACE_ROOT/spaces" ]]; then
    printf '%s\n' "$DATARIM_WORKSPACE_ROOT/spaces"
    return 0
  fi
  local dir="${PWD:-.}"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/spaces/registry.yml" ]]; then
      printf '%s\n' "$dir/spaces"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

_autonomy_marker_name() {
  local dir="${PWD:-.}" marker auto_marker
  while [[ "$dir" != "/" ]]; do
    auto_marker="$dir/datarim/.auto-mode-active"
    if [[ -f "$auto_marker" ]]; then
      yq eval -r '.space // ""' "$auto_marker" 2>/dev/null
      return 0
    fi
    marker="$dir/datarim/.space"
    if [[ -f "$marker" ]]; then
      yq eval -r '.space // .name // ""' "$marker" 2>/dev/null
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

_autonomy_space_file() {
  local spaces_root="$1" requested="${DATARIM_ACTIVE_SPACE:-${DATARIM_SPACE_NAME:-}}"
  if [[ -n "${DATARIM_SPACE_YML:-}" && -f "$DATARIM_SPACE_YML" ]]; then
    printf '%s\n' "$DATARIM_SPACE_YML"
    return 0
  fi
  if [[ -z "$requested" ]]; then
    requested="$(_autonomy_marker_name 2>/dev/null || true)"
  fi
  [[ "$requested" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || return 1
  if [[ -n "$requested" && -f "$spaces_root/$requested/space.yml" ]]; then
    printf '%s\n' "$spaces_root/$requested/space.yml"
    return 0
  fi
  return 1
}

_autonomy_effective_kind() {
  local action="$1" payload="$2" branch
  case "$action" in
    force_push)
      if [[ "$(jq -r 'if has("drops_commits") then .drops_commits else true end' \
        <<<"$payload" 2>/dev/null)" == true ]]; then
        printf '%s\n' force_push_drops_commits
      else
        branch="$(jq -r '.target_branch // ""' <<<"$payload" 2>/dev/null)"
        case "$branch" in
          main|master) printf '%s\n' merge_main ;;
          "") printf '%s\n' force_push_unknown ;;
          *) printf '%s\n' feature_branch_push ;;
        esac
      fi
      ;;
    irreversible_db_op)
      if [[ "$(jq -r '.backup_verified // false' <<<"$payload" 2>/dev/null)" == true ]]; then
        printf '%s\n' irreversible_db_op
      else
        printf '%s\n' irreversible_db_no_backup
      fi
      ;;
    *) printf '%s\n' "$action" ;;
  esac
}

_autonomy_operator() {
  local action="$1" effective="$2" reason="$3" floor_hit="${4:-false}"
  _autonomy_json \
    --arg action "$action" --arg effective "$effective" --arg reason "$reason" \
    --argjson floor "$floor_hit" \
    '{schema_version:1,action_kind:$action,effective_action_kind:$effective,
      decision:"operator",floor_hit:$floor,precedence_layer:(if $floor then "P0" else "P3" end),
      reason_code:$reason}'
  return 10
}

_autonomy_rules() {
  # Default to the core path so the floor resolves without the dr-orchestrate
  # plugin. Override by setting DR_AUTONOMY_RULES to an absolute path.
  local rules="${DR_AUTONOMY_RULES:-${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/rules/fb-rules.yaml}"
  [[ -n "$rules" && -s "$rules" ]] || return 1
  yq eval -e '.always_gated_floor | type == "!!seq" and length > 0' "$rules" >/dev/null 2>&1 \
    || return 1
  yq eval -e '.action_autonomy_map | type == "!!map" and length > 0' "$rules" >/dev/null 2>&1 \
    || return 1
  printf '%s\n' "$rules"
}

_autonomy_release_allowed() {
  local payload="$1"
  jq -e '
    (.bump_level == "patch" or .bump_level == "minor") and
    (.escalate == false) and
    (.zero_x_breaking != true)
  ' <<<"$payload" >/dev/null 2>&1
}

_autonomy_policy_decision() {
  local action="$1" effective="$2" rules="$3"
  local spaces_root space_yml policy_key policy_value space_name valid_policy
  spaces_root="$(_autonomy_spaces_root 2>/dev/null || true)"
  space_yml="$(_autonomy_space_file "$spaces_root" 2>/dev/null || true)"
  if [[ -z "$spaces_root" || -z "$space_yml" ]]; then
    _autonomy_operator "$action" "$effective" unresolved_space
    return 10
  fi
  policy_key="$(yq eval -r ".action_autonomy_map.\"$effective\" // \"\"" "$rules")"
  if [[ -z "$policy_key" ]]; then
    _autonomy_operator "$action" "$effective" unmapped_action
    return 10
  fi
  valid_policy="$(yq eval -r '
    .autonomy.schema_version == 1 and
    (.autonomy.policy | type == "!!map") and
    ([.autonomy.policy[] | (. == "auto" or . == "operator")] | all)
  ' "$space_yml" 2>/dev/null || printf false)"
  if [[ "$valid_policy" != true ]]; then
    _autonomy_operator "$action" "$effective" invalid_or_missing_autonomy
    return 10
  fi
  policy_value="$(yq eval -r ".autonomy.policy.\"$policy_key\" // \"operator\"" "$space_yml")"
  space_name="$(yq eval -r '.space.name // ""' "$space_yml")"
  _autonomy_json \
    --arg action "$action" --arg effective "$effective" --arg key "$policy_key" \
    --arg value "$policy_value" --arg space "$space_name" \
    '{schema_version:1,action_kind:$action,effective_action_kind:$effective,
      decision:$value,floor_hit:false,policy_key:$key,policy_value:$value,
      space:$space,space_source:"resolved_space_yml",precedence_layer:"P2",
      reason_code:"space_policy"}'
  [[ "$policy_value" == auto ]] && return 0
  return 10
}

autonomy_decision() {
  local action="$1" payload="${2:-"{}"}" rules effective floor_hit
  jq -e 'type == "object"' <<<"$payload" >/dev/null 2>&1 || payload='{}'
  effective="$(_autonomy_effective_kind "$action" "$payload")"
  rules="$(_autonomy_rules 2>/dev/null || true)"
  if [[ -z "$rules" ]]; then
    _autonomy_json --arg action "$action" \
      '{schema_version:1,action_kind:$action,decision:"operator",floor_hit:false,
        precedence_layer:"P0",reason_code:"invalid_rules"}'
    return 2
  fi
  floor_hit="$(yq eval -o=json '.always_gated_floor' "$rules" \
    | jq --arg kind "$effective" 'index($kind) != null')"
  if [[ "$floor_hit" == true ]]; then
    _autonomy_operator "$action" "$effective" always_gated_floor true
    return 10
  fi
  if [[ "$action" == public_package_release ]] \
    && ! _autonomy_release_allowed "$payload"; then
    _autonomy_json --arg action "$action" \
      '{schema_version:1,action_kind:$action,
        effective_action_kind:"public_package_release",decision:"operator",
        floor_hit:false,precedence_layer:"P1",
        reason_code:"release_carveout_denied"}'
    return 10
  fi
  _autonomy_policy_decision "$action" "$effective" "$rules"
}
