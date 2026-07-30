#!/usr/bin/env bash
# Verify version accountability for the committed task diff. Read-only.
set -euo pipefail
IFS=$'\n\t'

usage() {
  printf 'Usage: check-framework-version-accountability.sh --task ID --workspace DIR --repo DIR\n' >&2
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

sha256_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  else
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  fi
}

stat_owner() {
  stat -c '%u' "$1" 2>/dev/null || stat -f '%u' "$1"
}

stat_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

stat_identity() {
  stat -c '%d:%i:%s:%Y' "$1" 2>/dev/null || stat -f '%d:%i:%z:%m' "$1"
}

trusted_directory() {
  local path="$1" mode group_digit other_digit
  [ -d "$path" ] && [ ! -L "$path" ] || return 1
  [ "$(stat_owner "$path")" = "$(id -u)" ] || return 1
  mode="$(stat_mode "$path")"
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
  group_digit="${mode: -2:1}"
  other_digit="${mode: -1}"
  [ $((group_digit & 2)) -eq 0 ] && [ $((other_digit & 2)) -eq 0 ]
}

safe_workspace_directory() {
  local path="$1" mode other_digit
  [ -d "$path" ] && [ ! -L "$path" ] || return 1
  [ "$(stat_owner "$path")" = "$(id -u)" ] || return 1
  mode="$(stat_mode "$path")"
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
  other_digit="${mode: -1}"
  [ $((other_digit & 2)) -eq 0 ]
}

is_closed_ascii_record() {
  local path="$1" forbidden last_byte
  forbidden="$(LC_ALL=C tr -d '\12\40-\176' < "$path" | wc -c | tr -d '[:space:]')"
  [ "$forbidden" -eq 0 ] || return 1
  last_byte="$(tail -c 1 "$path" | od -An -tuC | tr -d '[:space:]')"
  [ "$last_byte" = 10 ]
}

is_shipped_path() {
  case "$1" in
    tests/*|*/tests/*|*/test/*|*/fixtures/*|.github/*|.datarim/*|VERSION|CHANGELOG.md|documentation/archive/*|documentation/evolution/*|documentation/ephemeral/*|documentation/release-audit/*) return 1 ;;
    commands/*|skills/*|agents/*|templates/*|plugins/*|cli/*|scripts/*|dev-tools/*|config/*|documentation/tutorials/*|documentation/how-to/*|documentation/reference/*|documentation/explanation/*) return 0 ;;
    install.sh|update.sh|validate.sh|accepted-risk-aal.yml|CLAUDE.md|README.md|CONTRIBUTING.md|SECURITY.md) return 0 ;;
    *) return 1 ;;
  esac
}

is_accountability_path() {
  case "$1" in
    VERSION|CHANGELOG.md|.datarim/version-deferrals/*) return 0 ;;
    *) is_shipped_path "$1" ;;
  esac
}

emit() {
  local disposition="$1" code="$2"
  printf 'framework-version-accountability: disposition=%s base=%s head=%s scope_digest=%s\n' \
    "$disposition" "$base_oid" "$head_oid" "$scope_digest"
  exit "$code"
}

fail_untrusted() {
  printf 'framework-version-accountability: error=%s\n' "$1" >&2
  emit untrustworthy_evidence 2
}

task="" workspace="" repo=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --task) [ "$#" -ge 2 ] || { usage; exit 2; }; task="$2"; shift 2 ;;
    --workspace) [ "$#" -ge 2 ] || { usage; exit 2; }; workspace="$2"; shift 2 ;;
    --repo) [ "$#" -ge 2 ] || { usage; exit 2; }; repo="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

base_oid="0000000000000000000000000000000000000000"
head_oid="0000000000000000000000000000000000000000"
scope_digest="0000000000000000000000000000000000000000000000000000000000000000"
if ! [[ "$task" =~ ^[A-Z]{2,10}-[0-9]{4}(-[A-Za-z0-9]+)*$ ]]; then fail_untrusted invalid_task; fi
if [ ! -d "$workspace" ] || [ ! -d "$repo" ] || [ -L "$workspace" ] || [ -L "$repo" ]; then fail_untrusted invalid_root; fi
workspace="$(cd "$workspace" && pwd -P)"
repo="$(cd "$repo" && pwd -P)"
trusted_directory "$repo" || fail_untrusted unsafe_repo
for component in "$workspace" "$workspace/datarim" "$workspace/datarim/tasks"; do
  safe_workspace_directory "$component" || fail_untrusted unsafe_workspace_path
done
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || fail_untrusted not_git_repo
head_oid="$(git -C "$repo" rev-parse 'HEAD^{commit}' 2>/dev/null)" || fail_untrusted invalid_head

record="$workspace/datarim/.auto/version-accountability/$task/baseline.record"
if [ ! -f "$record" ] || [ -L "$record" ]; then fail_untrusted missing_baseline; fi
[ "$(stat_owner "$record")" = "$(id -u)" ] || fail_untrusted baseline_owner
[ "$(stat_mode "$record")" = 600 ] || fail_untrusted baseline_mode
is_closed_ascii_record "$record" || fail_untrusted baseline_encoding
record_identity="$(stat_identity "$record")"
record_digest="$(sha256_file "$record")"
for component in "$workspace/datarim/.auto" "$workspace/datarim/.auto/version-accountability" "$(dirname "$record")"; do
  trusted_directory "$component" || fail_untrusted unsafe_baseline_path
done
[ "$(wc -c < "$record" | tr -d '[:space:]')" -le 1024 ] || fail_untrusted baseline_oversized

lines=()
while IFS= read -r line || [ -n "$line" ]; do lines[${#lines[@]}]="$line"; done < "$record"
[ "${#lines[@]}" -eq 7 ] || fail_untrusted baseline_schema
[ "${lines[0]}" = 'schema-version: 1' ] || fail_untrusted baseline_schema
[ "${lines[1]}" = "task-id: $task" ] || fail_untrusted baseline_task
[[ "${lines[2]}" == repo-root-sha256:\ * ]] || fail_untrusted baseline_schema
[[ "${lines[3]}" == base-commit:\ * ]] || fail_untrusted baseline_schema
[[ "${lines[4]}" == base-tree:\ * ]] || fail_untrusted baseline_schema
[[ "${lines[5]}" == init-task-sha256:\ * ]] || fail_untrusted baseline_schema
repo_digest="${lines[2]#repo-root-sha256: }"
base_oid="${lines[3]#base-commit: }"
base_tree="${lines[4]#base-tree: }"
init_digest="${lines[5]#init-task-sha256: }"
[[ "$repo_digest" =~ ^[a-f0-9]{64}$ ]] || fail_untrusted baseline_schema
[[ "$base_oid" =~ ^[a-f0-9]{40}$ ]] || fail_untrusted baseline_schema
[[ "$base_tree" =~ ^[a-f0-9]{40}$ ]] || fail_untrusted baseline_schema
[[ "$init_digest" =~ ^[a-f0-9]{64}$ ]] || fail_untrusted baseline_schema
[[ "${lines[6]}" =~ ^captured-at:[[:space:]][0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || fail_untrusted baseline_schema
[ "$repo_digest" = "$(sha256_text "$repo")" ] || fail_untrusted repository_mismatch
git -C "$repo" cat-file -e "$base_oid^{commit}" 2>/dev/null || fail_untrusted invalid_base
[ "$base_tree" = "$(git -C "$repo" rev-parse "$base_oid^{tree}")" ] || fail_untrusted base_tree_mismatch
git -C "$repo" merge-base --is-ancestor "$base_oid" "$head_oid" 2>/dev/null || fail_untrusted non_ancestor_base

init_task="$workspace/datarim/tasks/$task-init-task.md"
if [ ! -f "$init_task" ] || [ -L "$init_task" ]; then fail_untrusted missing_init_task; fi

dirty=0
status_file="$(mktemp)"
diff_file="$(mktemp)"
digest_file="$(mktemp)"
base_version_file="$(mktemp)"
head_version_file="$(mktemp)"
base_changelog="$(mktemp)"
head_changelog="$(mktemp)"
deferral_file="$(mktemp)"
# shellcheck disable=SC2317  # Called by the trap below.
cleanup() { rm -f -- "$status_file" "$diff_file" "$digest_file" "$base_version_file" "$head_version_file" "$base_changelog" "$head_changelog" "$deferral_file"; }
trap cleanup EXIT HUP INT TERM
has_relevant_dirty_state() {
  local entry status path paired_path
  while IFS= read -r -d '' entry; do
    [ "${#entry}" -ge 4 ] || return 2
    status="${entry:0:2}"
    path="${entry:3}"
    paired_path=""
    case "$status" in
      R*|C*) IFS= read -r -d '' paired_path || return 2 ;;
    esac
    if is_accountability_path "$path" \
      || { [ -n "$paired_path" ] && is_accountability_path "$paired_path"; }; then
      return 0
    fi
  done < "$1"
  return 1
}
emit_checked() {
  local disposition="$1" code="$2" status_result
  [ "$head_oid" = "$(git -C "$repo" rev-parse 'HEAD^{commit}')" ] || fail_untrusted head_changed
  [ "$base_tree" = "$(git -C "$repo" rev-parse "$base_oid^{tree}")" ] || fail_untrusted base_tree_changed
  [ "$record_identity" = "$(stat_identity "$record")" ] || fail_untrusted baseline_changed
  [ "$record_digest" = "$(sha256_file "$record")" ] || fail_untrusted baseline_changed
  [ "$(stat_owner "$record")" = "$(id -u)" ] || fail_untrusted baseline_owner
  [ "$(stat_mode "$record")" = 600 ] || fail_untrusted baseline_mode
  git -C "$repo" status --porcelain -z --untracked-files=all > "$status_file" || fail_untrusted git_status_failed
  if has_relevant_dirty_state "$status_file"; then
    fail_untrusted relevant_dirty_state
  else
    status_result=$?
    [ "$status_result" -eq 1 ] || fail_untrusted malformed_git_status
  fi
  emit "$disposition" "$code"
}
git -C "$repo" status --porcelain -z --untracked-files=all > "$status_file" || fail_untrusted git_status_failed
if has_relevant_dirty_state "$status_file"; then dirty=1; else status_result=$?; [ "$status_result" -eq 1 ] || fail_untrusted malformed_git_status; fi
[ "$dirty" -eq 0 ] || fail_untrusted relevant_dirty_state

git -C "$repo" diff --name-status -z -M -C "$base_oid" "$head_oid" > "$diff_file" || fail_untrusted git_diff_failed
printf 'datarim-framework-version-accountability-v1\0%s\0' "$base_oid" > "$digest_file"
shipped=0
while IFS= read -r -d '' status; do
  IFS= read -r -d '' old_path || fail_untrusted malformed_git_diff
  new_path="$old_path"
  case "$status" in
    R*|C*) IFS= read -r -d '' new_path || fail_untrusted malformed_git_diff ;;
  esac
  if is_shipped_path "$old_path" || is_shipped_path "$new_path"; then
    shipped=1
    printf '%s\0%s\0%s\0' "$status" "$old_path" "$new_path" >> "$digest_file"
    git -C "$repo" ls-tree -z "$base_oid" -- "$old_path" >> "$digest_file" || fail_untrusted git_tree_failed
    git -C "$repo" ls-tree -z "$head_oid" -- "$new_path" >> "$digest_file" || fail_untrusted git_tree_failed
  fi
done < "$diff_file"
scope_digest="$(sha256_file "$digest_file")"

git -C "$repo" show "$base_oid:VERSION" > "$base_version_file" 2>/dev/null || emit_checked invalid_version_transition 1
git -C "$repo" show "$head_oid:VERSION" > "$head_version_file" 2>/dev/null || emit_checked invalid_version_transition 1
[ "$(wc -l < "$base_version_file" | tr -d '[:space:]')" -eq 1 ] || emit_checked invalid_version_transition 1
[ "$(wc -l < "$head_version_file" | tr -d '[:space:]')" -eq 1 ] || emit_checked invalid_version_transition 1
base_version="$(tr -d '\n' < "$base_version_file")"
head_version="$(tr -d '\n' < "$head_version_file")"
semver_re='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
[[ "$base_version" =~ $semver_re ]] || emit_checked invalid_version_transition 1
[[ "$head_version" =~ $semver_re ]] || emit_checked invalid_version_transition 1

version_state=unchanged
if [ "$base_version" != "$head_version" ]; then
  IFS=. read -r b1 b2 b3 <<< "$base_version"
  IFS=. read -r h1 h2 h3 <<< "$head_version"
  if [ "$h1" -gt "$b1" ] \
    || { [ "$h1" -eq "$b1" ] && [ "$h2" -gt "$b2" ]; } \
    || { [ "$h1" -eq "$b1" ] && [ "$h2" -eq "$b2" ] && [ "$h3" -gt "$b3" ]; }; then
    version_state=increased
  else
    version_state=invalid
  fi
fi

record_path=".datarim/version-deferrals/$task.record"
record_present=0
if git -C "$repo" cat-file -e "$head_oid:$record_path" 2>/dev/null; then record_present=1; fi

if [ "$shipped" -eq 0 ] && [ "$version_state" = unchanged ]; then emit_checked not_applicable 0; fi
[ "$version_state" != invalid ] || emit_checked invalid_version_transition 1

changelog_ok=0
git -C "$repo" show "$base_oid:CHANGELOG.md" > "$base_changelog" 2>/dev/null || fail_untrusted missing_changelog
git -C "$repo" show "$head_oid:CHANGELOG.md" > "$head_changelog" 2>/dev/null || fail_untrusted missing_changelog
head_unreleased_count="$(grep -c '^## \[Unreleased\]$' "$head_changelog" || true)"
[ "$head_unreleased_count" -eq 1 ] || fail_untrusted malformed_changelog
extract_unreleased() {
  awk '/^## \[Unreleased\]$/ {inside=1; next} inside && /^## \[/ {exit} inside {print}' "$1"
}
if extract_unreleased "$head_changelog" | grep -Eq "^- .*([^A-Za-z0-9-]|^)${task}([^A-Za-z0-9-]|$)" \
  && ! extract_unreleased "$base_changelog" | grep -Eq "^- .*([^A-Za-z0-9-]|^)${task}([^A-Za-z0-9-]|$)"; then
  changelog_ok=1
fi

if [ "$version_state" = increased ]; then
  [ "$record_present" -eq 0 ] || emit_checked contradictory_evidence 1
  [ "$changelog_ok" -eq 1 ] || emit_checked changelog_missing 1
  emit_checked satisfied_by_version 0
fi

[ "$record_present" -eq 1 ] || emit_checked accountability_missing 1
mode_line="$(git -C "$repo" ls-tree "$head_oid" -- "$record_path")"
[[ "$mode_line" == 100644\ blob\ * ]] || fail_untrusted deferral_mode
git -C "$repo" show "$head_oid:$record_path" > "$deferral_file" 2>/dev/null || fail_untrusted deferral_read
[ "$(wc -c < "$deferral_file" | tr -d '[:space:]')" -le 2048 ] || fail_untrusted deferral_oversized
is_closed_ascii_record "$deferral_file" || fail_untrusted deferral_encoding
dlines=()
while IFS= read -r line || [ -n "$line" ]; do dlines[${#dlines[@]}]="$line"; done < "$deferral_file"
[ "${#dlines[@]}" -eq 13 ] || fail_untrusted deferral_schema
[ "${dlines[0]}" = 'schema-version: 1' ] || fail_untrusted deferral_schema
[ "${dlines[1]}" = "task-id: $task" ] || fail_untrusted deferral_task
[ "${dlines[2]}" = "base-commit: $base_oid" ] || fail_untrusted deferral_base
[ "${dlines[3]}" = "shipped-diff-digest: $scope_digest" ] || fail_untrusted deferral_digest
[ "${dlines[4]}" = 'decision: defer' ] || fail_untrusted deferral_schema
[[ "${dlines[5]}" == reason-code:\ * ]] || fail_untrusted deferral_schema
[[ "${dlines[6]}" == reason:\ * ]] || fail_untrusted deferral_schema
[[ "${dlines[7]}" == delivery-kind:\ * ]] || fail_untrusted deferral_schema
[[ "${dlines[8]}" == delivery-target:\ * ]] || fail_untrusted deferral_schema
reason_code="${dlines[5]#reason-code: }"
reason="${dlines[6]#reason: }"
delivery_kind="${dlines[7]#delivery-kind: }"
delivery_target="${dlines[8]#delivery-target: }"
[ "${dlines[9]}" = 'source-kind: init-task' ] || fail_untrusted deferral_source
[ "${dlines[10]}" = "source-digest: $init_digest" ] || fail_untrusted deferral_source
[ "${dlines[11]}" = 'recorded-by: agent' ] || fail_untrusted deferral_schema
[[ "${dlines[12]}" =~ ^recorded-at:[[:space:]][0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || fail_untrusted deferral_time
[[ "$reason_code" =~ ^(batch-accumulation|coordinated-release|operator-directed)$ ]] || fail_untrusted deferral_reason
[[ "$reason" =~ ^[A-Za-z0-9][A-Za-z0-9\ .,\(\)_-]{19,159}$ ]] || fail_untrusted deferral_reason
[[ "$delivery_kind" =~ ^(release-train|follow-up-task)$ ]] || fail_untrusted deferral_delivery
[[ "$delivery_target" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$ ]] || fail_untrusted deferral_delivery
if printf '%s\n%s\n' "$reason" "$delivery_target" | LC_ALL=C grep -Eqi '(@|/|\\|=|BEGIN |Bearer |token|password|secret|credential)'; then
  fail_untrusted deferral_sensitive_value
fi

emit_checked satisfied_by_deferral 0
