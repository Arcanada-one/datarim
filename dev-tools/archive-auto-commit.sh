#!/usr/bin/env bash
# Create a narrowly scoped local archive commit without invoking Git hooks.

set -euo pipefail

readonly PROGRAM="${0##*/}"
ACTION=""
TASK_ID=""
REPO_ARG=""
ARCHIVE_PATH=""
SNAPSHOT_PATH=""
STATE_DIR=""
STATE_FILE=""
LOCK_DIR=""
TEMP_INDEX=""
INDEX_LOCK=""
INDEX_LOCK_OWNED=0
TX_BRANCH=""
TX_HEAD=""
TX_INDEX_TREE=""
TX_PHASE=""
TX_JOURNAL_COMMIT=""
TX_NEW_TREE=""
TX_NEW_COMMIT=""
TX_STATE_DIGEST=""
TX_SOURCE_INDEX_DIGEST=""
TERMINAL_EMITTED=0

# The explicit --repo argument is the sole repository routing authority.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE \
  GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM
export GIT_OPTIONAL_LOCKS=0
export GIT_ATTR_NOSYSTEM=1

# Keep every worktree-content operation independent of per-user attributes.
# Repository and info attributes are inspected explicitly before any mutation.
git() {
  command git -c core.attributesFile=/dev/null "$@"
}

usage() {
  echo "Usage: $PROGRAM prepare --task ID --repo DIR" >&2
  echo "       $PROGRAM commit --task ID --repo DIR --archive PATH [--snapshot PATH]" >&2
  echo "       $PROGRAM skip --task ID" >&2
}

emit() {
  local disposition="$1"
  local detail="${2:-}"
  printf 'archive-auto-commit: task=%s disposition=%s' "$TASK_ID" "$disposition"
  if [[ -n "$detail" ]]; then
    printf ' %s' "$detail"
  fi
  printf '\n'
  TERMINAL_EMITTED=1
}

emit_phase() {
  local phase="$1"
  local detail="${2:-}"
  printf 'archive-auto-commit: task=%s phase=%s' "$TASK_ID" "$phase"
  if [[ -n "$detail" ]]; then
    printf ' %s' "$detail"
  fi
  printf '\n'
}

die_usage() {
  usage
  exit 2
}

cleanup() {
  if [[ "$INDEX_LOCK_OWNED" == 1 && -n "$INDEX_LOCK" && -e "$INDEX_LOCK" ]]; then
    rm -f -- "$INDEX_LOCK"
  fi
  [[ -n "$TEMP_INDEX" && -e "$TEMP_INDEX" ]] && rm -f -- "$TEMP_INDEX"
  if [[ -n "$LOCK_DIR" && -d "$LOCK_DIR" ]]; then
    rm -f -- "$LOCK_DIR/status" "$LOCK_DIR/final-status" "$LOCK_DIR/state.tmp" \
      "$LOCK_DIR/state.next" "$LOCK_DIR/commit-tree.err" "$LOCK_DIR/owner.pid"
  fi
  if [[ -n "$LOCK_DIR" && -d "$LOCK_DIR" ]]; then
    rmdir -- "$LOCK_DIR" 2>/dev/null || true
  fi
}

on_exit() {
  local rc=$?
  cleanup
  if [[ "$rc" -ne 0 && "$TERMINAL_EMITTED" == 0 ]]; then
    printf 'archive-auto-commit: task=%s disposition=integrity_error reason=unhandled-failure\n' \
      "${TASK_ID:-unknown}"
  fi
  return "$rc"
}
trap on_exit EXIT
trap 'exit 130' HUP INT TERM

sha256_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    return 1
  fi
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$1" | awk '{print $1}'
  else
    return 1
  fi
}

file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

file_uid() {
  stat -c '%u' "$1" 2>/dev/null || stat -f '%u' "$1"
}

file_nlink() {
  stat -c '%h' "$1" 2>/dev/null || stat -f '%l' "$1"
}

file_size() {
  stat -c '%s' "$1" 2>/dev/null || stat -f '%z' "$1"
}

canonical_dir() {
  (cd -- "$1" 2>/dev/null && pwd -P)
}

validate_task() {
  [[ "$TASK_ID" =~ ^[A-Z][A-Z0-9]*-[0-9]{4}$ ]] || die_usage
}

parse_args() {
  [[ $# -ge 1 ]] || die_usage
  ACTION="$1"
  shift
  case "$ACTION" in
    prepare|commit|skip) ;;
    -h|--help) usage; exit 0 ;;
    *) die_usage ;;
  esac

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task) [[ $# -ge 2 ]] || die_usage; TASK_ID="$2"; shift 2 ;;
      --repo) [[ $# -ge 2 ]] || die_usage; REPO_ARG="$2"; shift 2 ;;
      --archive) [[ $# -ge 2 ]] || die_usage; ARCHIVE_PATH="$2"; shift 2 ;;
      --snapshot) [[ $# -ge 2 ]] || die_usage; SNAPSHOT_PATH="$2"; shift 2 ;;
      *) die_usage ;;
    esac
  done

  validate_task
  if [[ "$ACTION" == skip ]]; then
    [[ -z "$REPO_ARG" && -z "$ARCHIVE_PATH" && -z "$SNAPSHOT_PATH" ]] || die_usage
    return
  fi
  [[ -n "$REPO_ARG" ]] || die_usage
  if [[ "$ACTION" == prepare ]]; then
    [[ -z "$ARCHIVE_PATH" && -z "$SNAPSHOT_PATH" ]] || die_usage
  else
    [[ -n "$ARCHIVE_PATH" ]] || die_usage
  fi
}

init_repo() {
  local canonical top git_state
  canonical="$(canonical_dir "$REPO_ARG")" || exit 2
  top="$(git -C "$canonical" rev-parse --show-toplevel 2>/dev/null)" || exit 2
  top="$(canonical_dir "$top")" || exit 2
  [[ "$canonical" == "$top" ]] || exit 2
  REPO_ARG="$top"

  git_state="$(git -C "$REPO_ARG" rev-parse --git-path datarim/archive-auto-commit)"
  if [[ "$git_state" != /* ]]; then
    git_state="$REPO_ARG/$git_state"
  fi
  STATE_DIR="$git_state"
  STATE_FILE="$STATE_DIR/$TASK_ID.record"

  [[ ! -L "$(dirname "$STATE_DIR")" ]] || exit 2
  mkdir -p -- "$STATE_DIR"
  [[ -d "$STATE_DIR" && ! -L "$STATE_DIR" ]] || exit 2
  chmod 700 "$STATE_DIR"
  [[ "$(file_uid "$STATE_DIR")" == "$(id -u)" ]] || exit 2
  LOCK_DIR="$STATE_DIR/$TASK_ID.lock"
  if ! mkdir -- "$LOCK_DIR" 2>/dev/null; then
    recover_stale_task_lock || { emit refused_race "reason=lock-busy"; exit 1; }
    mkdir -- "$LOCK_DIR" 2>/dev/null || { emit refused_race "reason=lock-busy"; exit 1; }
  fi
  chmod 700 "$LOCK_DIR"
  umask 077
  printf '%s\n' "$$" > "$LOCK_DIR/owner.pid"
}

recover_stale_task_lock() {
  local owner
  [[ -d "$LOCK_DIR" && ! -L "$LOCK_DIR" ]] || return 1
  [[ -f "$LOCK_DIR/owner.pid" && ! -L "$LOCK_DIR/owner.pid" ]] || return 1
  owner="$(sed -n '1p' "$LOCK_DIR/owner.pid")"
  [[ "$owner" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$owner" 2>/dev/null && return 1
  validate_state || return 1
  [[ "$(state_value phase)" == commit-created ]] || return 1
  rm -f -- "$LOCK_DIR/status" "$LOCK_DIR/final-status" "$LOCK_DIR/state.tmp" \
    "$LOCK_DIR/state.next" "$LOCK_DIR/commit-tree.err" "$LOCK_DIR/owner.pid"
  rmdir -- "$LOCK_DIR"
}

current_branch() {
  git -C "$REPO_ARG" symbolic-ref -q HEAD
}

real_index_path() {
  local path
  path="$(git -C "$REPO_ARG" rev-parse --git-path index)"
  [[ "$path" == /* ]] || path="$REPO_ARG/$path"
  printf '%s\n' "$path"
}

index_has_special_state() {
  local record flag shared_index
  while IFS= read -r -d '' record; do
    flag="${record:0:1}"
    [[ "$flag" == H ]] || return 0
  done < <(git -C "$REPO_ARG" ls-files -v -z)
  [[ "$(git -C "$REPO_ARG" config --bool core.sparseCheckout 2>/dev/null || true)" == true ]] && return 0
  [[ "$(git -C "$REPO_ARG" config --bool core.splitIndex 2>/dev/null || true)" == true ]] && return 0
  shared_index="$(git -C "$REPO_ARG" rev-parse --shared-index-path 2>/dev/null || true)"
  [[ -n "$shared_index" ]] && return 0
  return 1
}

filter_attributes_present() {
  local attributes git_attributes
  [[ -n "$(command git -C "$REPO_ARG" config --get core.attributesFile 2>/dev/null || true)" ]] && return 0
  while IFS= read -r -d '' attributes; do
    grep -Eq '(^|[[:space:]])!?filter([=[:space:]]|$)' "$REPO_ARG/$attributes" && return 0
  done < <(git -C "$REPO_ARG" ls-files -z -- '*gitattributes')
  git_attributes="$(git -C "$REPO_ARG" rev-parse --git-path info/attributes)"
  [[ "$git_attributes" == /* ]] || git_attributes="$REPO_ARG/$git_attributes"
  [[ -f "$git_attributes" ]] \
    && grep -Eq '(^|[[:space:]])!?filter([=[:space:]]|$)' "$git_attributes" && return 0
  return 1
}

validate_index_policy() {
  if index_has_special_state; then
    emit refused_manifest "reason=nonstandard-index"
    exit 1
  fi
  if filter_attributes_present; then
    emit refused_manifest "reason=external-filter-surface"
    exit 1
  fi
}

repo_digest() {
  printf '%s' "$REPO_ARG" | sha256_text
}

state_value() {
  local key="$1"
  sed -n "s/^${key}: //p" "$STATE_FILE"
}

validate_state() {
  local lines task digest branch head index_tree phase new_commit archive snapshot new_tree timestamp
  [[ -f "$STATE_FILE" && ! -L "$STATE_FILE" ]] || return 1
  [[ "$(file_mode "$STATE_FILE")" == 600 ]] || return 1
  [[ "$(file_uid "$STATE_FILE")" == "$(id -u)" ]] || return 1
  lines="$(wc -l < "$STATE_FILE" | tr -d ' ')"
  [[ "$lines" == 13 ]] || return 1
  sed -n '1p' "$STATE_FILE" | grep -qx 'schema-version: 1' || return 1
  sed -n '13p' "$STATE_FILE" | grep -qx 'state-end: archive-auto-commit-v1' || return 1

  task="$(state_value task-id)"
  digest="$(state_value repo-root-sha256)"
  branch="$(state_value branch-ref)"
  head="$(state_value head)"
  index_tree="$(state_value index-tree)"
  phase="$(state_value phase)"
  new_commit="$(state_value new-commit)"
  archive="$(state_value archive-path)"
  snapshot="$(state_value snapshot-path)"
  new_tree="$(state_value new-tree)"
  timestamp="$(state_value captured-at)"
  [[ "$task" == "$TASK_ID" ]] || return 1
  [[ "$digest" == "$(repo_digest)" ]] || return 1
  [[ "$branch" =~ ^refs/heads/[^[:cntrl:]]+$ ]] || return 1
  [[ "$head" =~ ^[0-9a-f]{40,64}$ ]] || return 1
  [[ "$index_tree" =~ ^[0-9a-f]{40,64}$ ]] || return 1
  [[ "$phase" == prepared || "$phase" == commit-created ]] || return 1
  if [[ "$phase" == prepared ]]; then
    [[ "$new_commit" == none && "$archive" == none && "$snapshot" == none \
      && "$new_tree" == none ]] || return 1
  else
    [[ "$new_commit" =~ ^[0-9a-f]{40,64}$ ]] || return 1
    [[ "$archive" =~ ^documentation/archive/[a-z][a-z0-9-]*/archive-${TASK_ID}\.md$ ]] || return 1
    [[ "$snapshot" == none \
      || "$snapshot" =~ ^documentation/archive/[a-z][a-z0-9-]*/snapshots/${TASK_ID}-final-stage\.md$ ]] || return 1
    [[ "$new_tree" =~ ^[0-9a-f]{40,64}$ ]] || return 1
  fi
  [[ "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
}

write_state_record() {
  local target="$1" phase="$2" new_commit="$3" branch="$4" head="$5" index_tree="$6" captured_at="$7"
  local archive="${8:-none}" snapshot="${9:-none}" new_tree="${10:-none}"
  umask 077
  {
    printf 'schema-version: 1\n'
    printf 'task-id: %s\n' "$TASK_ID"
    printf 'repo-root-sha256: %s\n' "$(repo_digest)"
    printf 'branch-ref: %s\n' "$branch"
    printf 'head: %s\n' "$head"
    printf 'index-tree: %s\n' "$index_tree"
    printf 'phase: %s\n' "$phase"
    printf 'new-commit: %s\n' "$new_commit"
    printf 'archive-path: %s\n' "$archive"
    printf 'snapshot-path: %s\n' "$snapshot"
    printf 'new-tree: %s\n' "$new_tree"
    printf 'captured-at: %s\n' "$captured_at"
    printf 'state-end: archive-auto-commit-v1\n'
  } > "$target"
  chmod 600 "$target"
}

advance_state() {
  local phase="$1" new_commit="$2" temp
  temp="$LOCK_DIR/state.next"
  write_state_record "$temp" "$phase" "$new_commit" \
    "$(state_value branch-ref)" "$(state_value head)" \
    "$(state_value index-tree)" "$(state_value captured-at)" \
    "$ARCHIVE_PATH" "${SNAPSHOT_PATH:-none}" "$TX_NEW_TREE"
  mv -- "$temp" "$STATE_FILE"
  if ! sync -f "$STATE_FILE" 2>/dev/null; then
    sync
  fi
  if ! sync -f "$STATE_DIR" 2>/dev/null; then
    sync
  fi
  TX_STATE_DIGEST="$(sha256_file "$STATE_FILE")"
}

remove_state() {
  [[ -e "$STATE_FILE" ]] && rm -f -- "$STATE_FILE"
}

has_staged_changes() {
  ! git -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$REPO_ARG" \
    diff --no-ext-diff --cached --quiet --ignore-submodules=none --
}

has_any_changes() {
  local status_file
  status_file="$LOCK_DIR/status"
  git -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$REPO_ARG" \
    status --porcelain=v1 -z --untracked-files=all --ignore-submodules=none > "$status_file"
  [[ -s "$status_file" ]]
}

runtime_paths_are_ignored() {
  local runtime_path
  for runtime_path in \
    datarim/tasks.md \
    datarim/activeContext.md \
    "datarim/plans/$TASK_ID-plan.md" \
    "datarim/reflection/reflection-$TASK_ID.md"; do
    if git -C "$REPO_ARG" ls-files --error-unmatch -- "$runtime_path" >/dev/null 2>&1; then
      return 1
    fi
    git -C "$REPO_ARG" check-ignore -q --no-index -- "$runtime_path" || return 1
  done
}

resume_pending_prepare() {
  if [[ -e "$STATE_FILE" ]] && validate_state \
    && [[ "$(state_value phase)" == commit-created ]]; then
    emit_phase prepared "state=recovery-ready"
    exit 0
  fi
}

do_prepare() {
  local branch head index_tree temp
  validate_index_policy
  resume_pending_prepare
  if has_staged_changes; then
    emit refused_staged
    exit 1
  fi
  if ! runtime_paths_are_ignored; then
    emit refused_manifest "reason=runtime-path-visible"
    exit 1
  fi
  if has_any_changes; then
    emit refused_dirty
    exit 1
  fi

  branch="$(current_branch)" || { emit refused_manifest "reason=detached-head"; exit 1; }
  head="$(git -C "$REPO_ARG" rev-parse --verify 'HEAD^{commit}')"
  index_tree="$(git -C "$REPO_ARG" write-tree)"
  [[ "$index_tree" == "$(git -C "$REPO_ARG" rev-parse "$head^{tree}")" ]] || {
    emit refused_staged
    exit 1
  }

  if [[ -e "$STATE_FILE" ]]; then
    if validate_state && [[ "$(state_value phase)" == commit-created ]]; then
      emit committed_recovery_required "reason=unfinished-transaction"
      exit 2
    fi
    if validate_state && [[ "$(state_value branch-ref)" == "$branch" ]] \
      && [[ "$(state_value head)" == "$head" ]] \
      && [[ "$(state_value index-tree)" == "$index_tree" ]]; then
      emit_phase prepared "state=reused"
      exit 0
    fi
    emit refused_manifest "reason=state-conflict"
    exit 1
  fi

  temp="$LOCK_DIR/state.tmp"
  write_state_record "$temp" prepared none "$branch" "$head" "$index_tree" \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  mv -- "$temp" "$STATE_FILE"
  emit_phase prepared "state=captured"
}

area_prefix_to_subdir() {
  case "${1%%-*}" in
    INFRA) echo infrastructure ;; WEB) echo web ;; CONTENT) echo content ;;
    RESEARCH) echo research ;; AGENT) echo agents ;; BENCH) echo benchmarks ;;
    DEV) echo development ;; DEVOPS) echo devops ;; TUNE|ROB) echo framework ;;
    MAINT) echo maintenance ;; FIN) echo finance ;; QA) echo qa ;;
    SEC) echo security ;; QCK) echo quick ;; *) return 1 ;;
  esac
}

project_prefix_to_subdir() {
  local prefix="$1" cursor="$REPO_ARG" result
  while [[ "$cursor" != / ]]; do
    if [[ -f "$cursor/CLAUDE.md" && ! -L "$cursor/CLAUDE.md" ]]; then
      result="$(awk -v p="$prefix" '
        /^#{2,6} Task Prefix Registry/ { section=1; next }
        section && /^#{1,6} / { section=0 }
        section && /^\| *[A-Z][A-Z0-9_-]* *\|/ {
          n=split($0,f,"|"); if (n<4) next
          key=f[2]; gsub(/^ +| +$/,"",key)
          if (key==p) { area=f[4]; gsub(/^ +| +$/,"",area); print area; exit }
        }
      ' "$cursor/CLAUDE.md")"
      if [[ -n "$result" ]]; then
        [[ "$result" =~ ^[a-z][a-z0-9-]*$ ]] || return 1
        printf '%s\n' "$result"
        return 0
      fi
    fi
    cursor="$(dirname "$cursor")"
  done
  return 1
}

canonical_archive_area() {
  local prefix="${TASK_ID%%-*}" area
  if area="$(area_prefix_to_subdir "$prefix")"; then
    printf '%s\n' "$area"
  elif area="$(project_prefix_to_subdir "$prefix")"; then
    printf '%s\n' "$area"
  else
    printf 'general\n'
  fi
}

validate_manifest() {
  local area expected_area archive_re snapshot_re candidate component part
  local -a path_parts
  [[ "$ARCHIVE_PATH" != /* && "$ARCHIVE_PATH" != *'..'* && "$ARCHIVE_PATH" != *$'\n'* \
    && "$ARCHIVE_PATH" != *$'\r'* && "$ARCHIVE_PATH" != *$'\t'* ]] || return 1
  archive_re="^documentation/archive/([a-z][a-z0-9-]*)/archive-${TASK_ID}\\.md$"
  [[ "$ARCHIVE_PATH" =~ $archive_re ]] || return 1
  area="${BASH_REMATCH[1]}"
  expected_area="$(canonical_archive_area)" || return 1
  [[ "$area" == "$expected_area" ]] || return 1
  if [[ -n "$SNAPSHOT_PATH" ]]; then
    [[ "$SNAPSHOT_PATH" != /* && "$SNAPSHOT_PATH" != *'..'* && "$SNAPSHOT_PATH" != *$'\n'* \
      && "$SNAPSHOT_PATH" != *$'\r'* && "$SNAPSHOT_PATH" != *$'\t'* ]] || return 1
    snapshot_re="^documentation/archive/${area}/snapshots/${TASK_ID}-final-stage\\.md$"
    [[ "$SNAPSHOT_PATH" =~ $snapshot_re ]] || return 1
    [[ "$SNAPSHOT_PATH" != "$ARCHIVE_PATH" ]] || return 1
  fi

  for candidate in "$ARCHIVE_PATH" ${SNAPSHOT_PATH:+"$SNAPSHOT_PATH"}; do
    [[ -f "$REPO_ARG/$candidate" && ! -L "$REPO_ARG/$candidate" ]] || return 1
    [[ "$(file_nlink "$REPO_ARG/$candidate")" == 1 ]] || return 1
    [[ ! -x "$REPO_ARG/$candidate" ]] || return 1
    component="$REPO_ARG"
    IFS='/' read -r -a path_parts <<< "$candidate"
    for part in "${path_parts[@]}"; do
      component="$component/$part"
      [[ ! -L "$component" ]] || return 1
    done
    if git -C "$REPO_ARG" check-ignore -q -- "$candidate"; then
      return 1
    fi
  done

  validate_archive_content "$REPO_ARG/$ARCHIVE_PATH" || return 1
  if [[ -n "$SNAPSHOT_PATH" ]]; then
    validate_snapshot_content "$REPO_ARG/$SNAPSHOT_PATH" || return 1
  fi
}

validate_archive_content() {
  local file="$1"
  [[ "$(file_size "$file")" -gt 0 && "$(file_size "$file")" -le 1048576 ]] || return 1
  [[ "$(sed -n '1p' "$file")" == '---' ]] || return 1
  frontmatter_is_closed "$file" || return 1
  [[ "$(frontmatter_value "$file" id)" == "$TASK_ID" ]] || return 1
  [[ "$(frontmatter_value "$file" status)" == archived ]] || return 1
  [[ "$(frontmatter_value "$file" archive_doc)" == "$ARCHIVE_PATH" ]] || return 1
  frontmatter_has_key "$file" verification_outcome || return 1
  grep -qx '### Acceptance Criteria' "$file" || return 1
  grep -qx '### Operator Handoff' "$file" || return 1
  grep -qx '### Related' "$file" || return 1
}

validate_snapshot_content() {
  local file="$1"
  [[ "$(file_size "$file")" -gt 0 && "$(file_size "$file")" -le 8192 ]] || return 1
  [[ "$(sed -n '1p' "$file")" == '---' ]] || return 1
  frontmatter_is_closed "$file" || return 1
  [[ "$(frontmatter_value "$file" task_id)" == "$TASK_ID" ]] || return 1
  [[ "$(frontmatter_value "$file" artifact)" == stage-snapshot ]] || return 1
  [[ "$(frontmatter_value "$file" schema_version)" == 1 ]] || return 1
  [[ "$(frontmatter_value "$file" stage)" =~ ^(init|prd|design|plan|do|qa|compliance|archive)$ ]] || return 1
}

frontmatter_value() {
  local file="$1" key="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_frontmatter=1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && index($0, key ":") == 1 {
      value=substr($0, length(key)+2); sub(/^ +/, "", value); print value; exit
    }
  ' "$file"
}

frontmatter_has_key() {
  local file="$1" key="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_frontmatter=1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && ($0 == key ":" || index($0, key ": ") == 1) { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$file"
}

frontmatter_is_closed() {
  awk 'NR == 1 && $0 == "---" { opened=1; next }
    opened && $0 == "---" { closed=1; exit }
    END { exit(closed ? 0 : 1) }' "$1"
}

is_candidate() {
  [[ "$1" == "$ARCHIVE_PATH" || (-n "$SNAPSHOT_PATH" && "$1" == "$SNAPSHOT_PATH") ]]
}

validate_dirty_set() {
  local status_file record xy path count=0
  status_file="$LOCK_DIR/final-status"
  git -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$REPO_ARG" \
    status --porcelain=v1 -z --untracked-files=all --ignore-submodules=none > "$status_file"
  while IFS= read -r -d '' record; do
    [[ ${#record} -ge 4 ]] || return 1
    xy="${record:0:2}"
    path="${record:3}"
    if [[ "$xy" == *R* || "$xy" == *C* ]]; then
      IFS= read -r -d '' _ || true
      return 1
    fi
    [[ "${xy:0:1}" == ' ' || "${xy:0:1}" == '?' ]] || return 2
    is_candidate "$path" || return 1
    count=$((count + 1))
  done < "$status_file"
  [[ "$count" -gt 0 ]] || return 3
  return 0
}

worktree_matches_tree() {
  local tree="$1" candidate expected actual
  for candidate in "$ARCHIVE_PATH" ${SNAPSHOT_PATH:+"$SNAPSHOT_PATH"}; do
    expected="$(git -C "$REPO_ARG" rev-parse "$tree:$candidate" 2>/dev/null)" || return 1
    actual="$(git -C "$REPO_ARG" hash-object --no-filters -- "$candidate")" || return 1
    [[ "$expected" == "$actual" ]] || return 1
  done
}

install_recovery_index() {
  local new_commit="$1" old_index_tree="$2" new_tree index_path index_digest candidate blob
  new_tree="$(git -C "$REPO_ARG" rev-parse "$new_commit^{tree}")"
  [[ "$(git -C "$REPO_ARG" write-tree)" == "$old_index_tree" ]] || {
    emit committed_recovery_required "reason=index-diverged"
    exit 2
  }
  TEMP_INDEX="$(mktemp "$STATE_DIR/index.XXXXXX")"
  index_path="$(real_index_path)"
  [[ -f "$index_path" && ! -L "$index_path" ]] || {
    emit committed_recovery_required "reason=index-invalid"
    exit 2
  }
  index_digest="$(sha256_file "$index_path")"
  cp -p -- "$index_path" "$TEMP_INDEX"
  for candidate in "$ARCHIVE_PATH" ${SNAPSHOT_PATH:+"$SNAPSHOT_PATH"}; do
    blob="$(git -C "$REPO_ARG" rev-parse "$new_commit:$candidate")"
    GIT_INDEX_FILE="$TEMP_INDEX" git -c core.hooksPath=/dev/null -c core.fsmonitor=false \
      -C "$REPO_ARG" update-index --add --cacheinfo "100644,$blob,$candidate"
  done
  INDEX_LOCK="$index_path.lock"
  ln -- "$TEMP_INDEX" "$INDEX_LOCK" 2>/dev/null || {
    emit committed_recovery_required "reason=index-lock-busy"
    exit 2
  }
  INDEX_LOCK_OWNED=1
  [[ "$(sha256_file "$index_path")" == "$index_digest" ]] || {
    emit committed_recovery_required "reason=index-changed"
    exit 2
  }
  if index_has_special_state || filter_attributes_present; then
    emit committed_recovery_required "reason=index-policy-changed"
    exit 2
  fi
  mv -- "$INDEX_LOCK" "$index_path" || {
    emit committed_recovery_required "reason=index-install-failed"
    exit 2
  }
  INDEX_LOCK=""
  INDEX_LOCK_OWNED=0
  remove_state
  emit committed "commit=$new_commit recovered=true"
  exit 0
}

recover_commit_created() {
  local branch="$1" old_head="$2" old_index_tree="$3" new_commit="$4"
  local current_head new_tree actual_tree parent
  parent="$(git -C "$REPO_ARG" rev-parse "$new_commit^" 2>/dev/null || true)"
  [[ "$parent" == "$old_head" ]] || {
    emit committed_recovery_required "reason=journal-parent-mismatch"; exit 2;
  }
  [[ "$(current_branch 2>/dev/null || true)" == "$branch" ]] || {
    emit committed_recovery_required "reason=journal-branch-mismatch"; exit 2;
  }
  current_head="$(git -C "$REPO_ARG" rev-parse HEAD)"
  [[ "$current_head" != "$old_head" ]] || return 3
  if [[ "$current_head" != "$new_commit" ]]; then
    remove_state; emit refused_race "reason=branch-moved"; exit 1
  fi
  new_tree="$(git -C "$REPO_ARG" rev-parse "$new_commit^{tree}")"
  worktree_matches_tree "$new_tree" || {
    emit committed_recovery_required "reason=working-tree-diverged"; exit 2;
  }
  actual_tree="$(git -C "$REPO_ARG" write-tree)"
  if [[ "$actual_tree" == "$new_tree" ]]; then
    remove_state; emit committed "commit=$new_commit recovered=true"; exit 0
  fi
  install_recovery_index "$new_commit" "$old_index_tree"
}

handle_missing_state() {
  if validate_manifest && ! has_any_changes && ! has_staged_changes \
    && git -C "$REPO_ARG" cat-file -e "HEAD:$ARCHIVE_PATH" 2>/dev/null \
    && { [[ -z "$SNAPSHOT_PATH" ]] || git -C "$REPO_ARG" cat-file -e "HEAD:$SNAPSHOT_PATH" 2>/dev/null; }; then
    emit already_clean
    exit 0
  fi
  emit refused_manifest "reason=missing-state"
  exit 1
}

load_transaction() {
  local recovery_rc=0 recorded_archive recorded_snapshot recorded_tree
  validate_state || { remove_state; emit refused_manifest "reason=invalid-state"; exit 1; }
  if index_has_special_state || filter_attributes_present; then
    remove_state; emit refused_race "reason=index-policy-changed"; exit 1
  fi
  TX_STATE_DIGEST="$(sha256_file "$STATE_FILE")"
  validate_manifest || { remove_state; emit refused_manifest "reason=invalid-path"; exit 1; }
  TX_BRANCH="$(state_value branch-ref)"
  TX_HEAD="$(state_value head)"
  TX_INDEX_TREE="$(state_value index-tree)"
  TX_PHASE="$(state_value phase)"
  TX_JOURNAL_COMMIT="$(state_value new-commit)"
  if [[ "$TX_PHASE" == commit-created ]]; then
    recorded_archive="$(state_value archive-path)"
    recorded_snapshot="$(state_value snapshot-path)"
    recorded_tree="$(state_value new-tree)"
    [[ "$recorded_archive" == "$ARCHIVE_PATH" \
      && "$recorded_snapshot" == "${SNAPSHOT_PATH:-none}" \
      && "$(git -C "$REPO_ARG" rev-parse "$TX_JOURNAL_COMMIT^{tree}")" == "$recorded_tree" ]] || {
      emit committed_recovery_required "reason=journal-manifest-mismatch"; exit 2;
    }
    recover_commit_created "$TX_BRANCH" "$TX_HEAD" "$TX_INDEX_TREE" \
      "$TX_JOURNAL_COMMIT" || recovery_rc=$?
    [[ "$recovery_rc" == 3 ]] || exit "$recovery_rc"
  fi
}

validate_transaction_state() {
  local dirty_result=0
  if [[ -e "$(real_index_path).lock" ]]; then
    remove_state; emit refused_race "reason=index-lock-busy"; exit 1
  fi
  if [[ "$(current_branch 2>/dev/null || true)" != "$TX_BRANCH" \
    || "$(git -C "$REPO_ARG" rev-parse --verify HEAD 2>/dev/null || true)" != "$TX_HEAD" ]]; then
    remove_state; emit refused_race "reason=branch-moved"; exit 1
  fi
  if has_staged_changes || [[ "$(git -C "$REPO_ARG" write-tree)" != "$TX_INDEX_TREE" ]]; then
    remove_state; emit refused_staged; exit 1
  fi
  validate_dirty_set || dirty_result=$?
  case "$dirty_result" in
    0) ;;
    2) remove_state; emit refused_staged; exit 1 ;;
    3) remove_state; emit already_clean; exit 0 ;;
    *) remove_state; emit refused_dirty; exit 1 ;;
  esac
}

build_candidate_index() {
  local candidate candidate_blob current_tree index_path
  TEMP_INDEX="$(mktemp "$STATE_DIR/index.XXXXXX")"
  index_path="$(real_index_path)"
  TX_SOURCE_INDEX_DIGEST="$(sha256_file "$index_path")"
  cp -p -- "$index_path" "$TEMP_INDEX"
  for candidate in "$ARCHIVE_PATH" ${SNAPSHOT_PATH:+"$SNAPSHOT_PATH"}; do
    candidate_blob="$(git -C "$REPO_ARG" hash-object -w --no-filters -- "$candidate")"
    GIT_INDEX_FILE="$TEMP_INDEX" git -c core.hooksPath=/dev/null -c core.fsmonitor=false \
      -C "$REPO_ARG" update-index --add --cacheinfo "100644,$candidate_blob,$candidate"
  done
  TX_NEW_TREE="$(GIT_INDEX_FILE="$TEMP_INDEX" git -C "$REPO_ARG" write-tree)"
  current_tree="$(git -C "$REPO_ARG" rev-parse "$TX_HEAD^{tree}")"
  if [[ "$TX_NEW_TREE" == "$current_tree" ]]; then
    remove_state; emit already_clean; exit 0
  fi
}

recheck_transaction() {
  validate_dirty_set || {
    remove_state; emit refused_race "reason=working-tree-changed"; exit 1;
  }
  worktree_matches_tree "$TX_NEW_TREE" || {
    remove_state; emit refused_race "reason=working-tree-changed"; exit 1;
  }
  [[ "$(current_branch)" == "$TX_BRANCH" \
    && "$(git -C "$REPO_ARG" rev-parse HEAD)" == "$TX_HEAD" \
    && "$(git -C "$REPO_ARG" write-tree)" == "$TX_INDEX_TREE" ]] || {
    remove_state; emit refused_race "reason=repository-changed"; exit 1;
  }
}

select_commit_object() {
  if [[ "$TX_PHASE" == commit-created ]]; then
    TX_NEW_COMMIT="$TX_JOURNAL_COMMIT"
    [[ "$(git -C "$REPO_ARG" rev-parse "$TX_NEW_COMMIT^{tree}")" == "$TX_NEW_TREE" ]] || {
      emit committed_recovery_required "reason=journal-tree-mismatch"; exit 2;
    }
    return
  fi
  if ! TX_NEW_COMMIT="$(printf 'chore(archive): record %s\n\n' "$TASK_ID" | \
    git -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$REPO_ARG" \
    commit-tree "$TX_NEW_TREE" -p "$TX_HEAD" 2>"$LOCK_DIR/commit-tree.err")"; then
    emit integrity_error "reason=commit-object-failed"
    exit 2
  fi
  advance_state commit-created "$TX_NEW_COMMIT"
}

advance_ref_and_index() {
  local index_path dirty_result=0
  index_path="$(real_index_path)"
  [[ -f "$index_path" && ! -L "$index_path" ]] || {
    remove_state; emit refused_race "reason=index-invalid"; exit 1;
  }
  INDEX_LOCK="$index_path.lock"
  ln -- "$TEMP_INDEX" "$INDEX_LOCK" 2>/dev/null || {
    remove_state; emit refused_race "reason=index-lock-busy"; exit 1;
  }
  INDEX_LOCK_OWNED=1
  [[ "$(sha256_file "$index_path")" == "$TX_SOURCE_INDEX_DIGEST" ]] || {
    remove_state; emit refused_race "reason=index-changed"; exit 1;
  }
  validate_index_policy
  if ! validate_state || [[ "$(sha256_file "$STATE_FILE")" != "$TX_STATE_DIGEST" ]]; then
    emit committed_recovery_required "reason=journal-changed"
    exit 2
  fi
  validate_dirty_set || dirty_result=$?
  if [[ "$dirty_result" != 0 ]] || ! worktree_matches_tree "$TX_NEW_TREE"; then
    remove_state; emit refused_race "reason=pre-ref-working-tree-changed"; exit 1
  fi
  git -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$REPO_ARG" \
    update-ref "$TX_BRANCH" "$TX_NEW_COMMIT" "$TX_HEAD" || {
    remove_state; emit refused_race "reason=ref-moved"; exit 1;
  }
  if ! GIT_INDEX_FILE="$TEMP_INDEX" git -c core.hooksPath=/dev/null \
    -c core.fsmonitor=false -C "$REPO_ARG" diff --no-ext-diff --quiet --ignore-submodules=none -- \
    || [[ -n "$(GIT_INDEX_FILE="$TEMP_INDEX" git -c core.hooksPath=/dev/null \
      -c core.fsmonitor=false -C "$REPO_ARG" ls-files --others --exclude-standard)" ]]; then
    if git -c core.hooksPath=/dev/null -c core.fsmonitor=false -C "$REPO_ARG" \
      update-ref "$TX_BRANCH" "$TX_HEAD" "$TX_NEW_COMMIT"; then
      remove_state; emit refused_race "reason=post-cas-working-tree-changed"; exit 1
    fi
    emit committed_recovery_required "reason=post-cas-rollback-lost commit=$TX_NEW_COMMIT"
    exit 2
  fi
  mv -- "$INDEX_LOCK" "$index_path" || {
    emit committed_recovery_required "reason=index-install-failed commit=$TX_NEW_COMMIT"; exit 2;
  }
  INDEX_LOCK=""
  INDEX_LOCK_OWNED=0
  remove_state
  if has_any_changes; then
    emit integrity_error "reason=post-commit-dirty commit=$TX_NEW_COMMIT"
    exit 2
  fi
  emit committed "commit=$TX_NEW_COMMIT"
}

do_commit() {
  [[ -e "$STATE_FILE" ]] || handle_missing_state
  load_transaction
  validate_transaction_state
  build_candidate_index
  recheck_transaction
  select_commit_object
  recheck_transaction
  advance_ref_and_index
}

parse_args "$@"
if [[ "$ACTION" == skip ]]; then
  emit skipped_disabled
  exit 0
fi
init_repo
case "$ACTION" in
  prepare) do_prepare ;;
  commit) do_commit ;;
esac
