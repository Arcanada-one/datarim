#!/usr/bin/env bash
# Capture the immutable INIT-owned repository baseline for version accountability.
set -euo pipefail
# nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering -- intentional strict-mode IFS scope is process-wide, single-script
IFS=$'\n\t'

usage() {
  printf 'Usage: capture-framework-version-baseline.sh --task ID --workspace DIR --repo DIR\n' >&2
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
# The repository root is only ever READ (through git). It therefore needs the same
# guarantee as $workspace — owned by us, not a symlink, not world-writable — and NOT
# the stricter no-group-write rule that trusted_directory() enforces for the record
# directory it creates. A default umask of 0002 yields mode 775 on every checkout, so
# demanding a clear group-write bit here rejects the normal shape of a shared dev host
# and hard-fails /dr-init for framework tasks.
safe_repo_directory() {
  safe_workspace_directory "$1"
}

is_closed_ascii_record() {
  local path="$1" forbidden last_byte
  forbidden="$(LC_ALL=C tr -d '\12\40-\176' < "$path" | wc -c | tr -d '[:space:]')"
  [ "$forbidden" -eq 0 ] || return 1
  last_byte="$(tail -c 1 "$path" | od -An -tuC | tr -d '[:space:]')"
  [ "$last_byte" = 10 ]
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

if ! [[ "$task" =~ ^[A-Z][A-Z0-9]{1,9}-[0-9]{4}(-[A-Za-z0-9]+)*$ ]]; then
  printf 'framework-version-baseline: error=invalid_task\n' >&2
  exit 2
fi
if [ ! -d "$workspace" ] || [ ! -d "$repo" ] || [ -L "$workspace" ] || [ -L "$repo" ]; then
  printf 'framework-version-baseline: error=invalid_root\n' >&2
  exit 2
fi
workspace="$(cd "$workspace" && pwd -P)"
repo="$(cd "$repo" && pwd -P)"
safe_repo_directory "$repo" || { printf 'framework-version-baseline: error=unsafe_repo\n' >&2; exit 2; }
for component in "$workspace" "$workspace/datarim" "$workspace/datarim/tasks"; do
  safe_workspace_directory "$component" || { printf 'framework-version-baseline: error=unsafe_workspace_path\n' >&2; exit 2; }
done
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { printf 'framework-version-baseline: error=not_git_repo\n' >&2; exit 2; }

init_task="$workspace/datarim/tasks/$task-init-task.md"
if [ ! -f "$init_task" ] || [ -L "$init_task" ]; then
  printf 'framework-version-baseline: error=missing_init_task\n' >&2
  exit 2
fi

record_dir="$workspace/datarim/.auto/version-accountability/$task"
record="$record_dir/baseline.record"
head_oid="$(git -C "$repo" rev-parse 'HEAD^{commit}')"
tree_oid="$(git -C "$repo" rev-parse 'HEAD^{tree}')"
repo_digest="$(sha256_text "$repo")"
init_digest="$(sha256_file "$init_task")"

if [ -f "$record" ] && [ ! -L "$record" ]; then
  for component in "$workspace/datarim/.auto" "$workspace/datarim/.auto/version-accountability" "$record_dir"; do
    trusted_directory "$component" || { printf 'framework-version-baseline: error=unsafe_path\n' >&2; exit 2; }
  done
  existing_lines=()
  while IFS= read -r line || [ -n "$line" ]; do existing_lines[${#existing_lines[@]}]="$line"; done < "$record"
  existing_repo_digest="${existing_lines[2]-}"
  existing_repo_digest="${existing_repo_digest#repo-root-sha256: }"
  existing_base="${existing_lines[3]-}"
  existing_base="${existing_base#base-commit: }"
  existing_tree="${existing_lines[4]-}"
  existing_tree="${existing_tree#base-tree: }"
  existing_init_digest="${existing_lines[5]-}"
  existing_init_digest="${existing_init_digest#init-task-sha256: }"
  if [ "$(stat_owner "$record")" != "$(id -u)" ] \
    || [ "$(stat_mode "$record")" != 600 ] \
    || ! is_closed_ascii_record "$record" \
    || [ "${#existing_lines[@]}" -ne 7 ] \
    || [ "${existing_lines[0]}" != 'schema-version: 1' ] \
    || [ "${existing_lines[1]}" != "task-id: $task" ] \
    || ! [[ "${existing_lines[2]}" == repo-root-sha256:\ * ]] \
    || ! [[ "${existing_lines[3]}" == base-commit:\ * ]] \
    || ! [[ "${existing_lines[4]}" == base-tree:\ * ]] \
    || ! [[ "${existing_lines[5]}" == init-task-sha256:\ * ]] \
    || [ "$existing_repo_digest" != "$repo_digest" ] \
    || ! [[ "$existing_base" =~ ^[a-f0-9]{40}$ ]] \
    || ! [[ "$existing_tree" =~ ^[a-f0-9]{40}$ ]] \
    || ! [[ "$existing_init_digest" =~ ^[a-f0-9]{64}$ ]] \
    || ! [[ "${existing_lines[6]}" =~ ^captured-at:[[:space:]][0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
    || ! git -C "$repo" cat-file -e "$existing_base^{commit}" 2>/dev/null \
    || [ "$existing_tree" != "$(git -C "$repo" rev-parse "$existing_base^{tree}" 2>/dev/null)" ] \
    || ! git -C "$repo" merge-base --is-ancestor "$existing_base" "$head_oid" 2>/dev/null; then
    printf 'framework-version-baseline: error=record_conflict\n' >&2
    exit 2
  fi
  printf 'framework-version-baseline: disposition=baseline_reused base=%s\n' "$existing_base"
  exit 0
fi
[ ! -e "$record" ] || { printf 'framework-version-baseline: error=unsafe_record\n' >&2; exit 2; }

if [ -e "$workspace/datarim/prd/PRD-$task.md" ] \
  || [ -e "$workspace/datarim/plans/$task-plan.md" ]; then
  printf 'framework-version-baseline: error=late_capture\n' >&2
  exit 2
fi

if [ -n "$(git -C "$repo" status --porcelain --untracked-files=all)" ]; then
  printf 'framework-version-baseline: error=dirty_repository\n' >&2
  exit 2
fi

umask 077
for component in "$workspace/datarim/.auto" "$workspace/datarim/.auto/version-accountability" "$record_dir"; do
  if [ ! -e "$component" ]; then
    mkdir -- "$component" || { printf 'framework-version-baseline: error=unsafe_path\n' >&2; exit 2; }
    chmod 700 "$component"
  fi
  if ! trusted_directory "$component"; then
    printf 'framework-version-baseline: error=unsafe_path\n' >&2
    exit 2
  fi
done

tmp="$(mktemp "$record_dir/.baseline.XXXXXX")"
cleanup() { rm -f -- "$tmp"; }
trap cleanup EXIT HUP INT TERM
captured_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
printf '%s\n' \
  'schema-version: 1' \
  "task-id: $task" \
  "repo-root-sha256: $repo_digest" \
  "base-commit: $head_oid" \
  "base-tree: $tree_oid" \
  "init-task-sha256: $init_digest" \
  "captured-at: $captured_at" > "$tmp"
chmod 600 "$tmp"
is_closed_ascii_record "$tmp" || { printf 'framework-version-baseline: error=record_encoding\n' >&2; exit 2; }
tmp_identity="$(stat_identity "$tmp")"
if ! ln "$tmp" "$record" 2>/dev/null; then
  printf 'framework-version-baseline: error=record_collision\n' >&2
  exit 2
fi
[ "$(stat_identity "$record")" = "$tmp_identity" ] || { printf 'framework-version-baseline: error=record_identity\n' >&2; exit 2; }
rm -f -- "$tmp"
trap - EXIT HUP INT TERM
printf 'framework-version-baseline: disposition=baseline_created base=%s\n' "$head_oid"
