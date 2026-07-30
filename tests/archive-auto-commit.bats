#!/usr/bin/env bats

setup() {
  export SOURCE_ROOT="$BATS_TEST_DIRNAME/.."
  export HELPER="$SOURCE_ROOT/dev-tools/archive-auto-commit.sh"
  export TEST_ROOT="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$TEST_ROOT"
  git -C "$TEST_ROOT" init -q
  git -C "$TEST_ROOT" config user.name "Datarim Test"
  git -C "$TEST_ROOT" config user.email "datarim@example.invalid"
  printf 'seed\n' > "$TEST_ROOT/README.md"
  printf 'datarim/\n' > "$TEST_ROOT/.gitignore"
  git -C "$TEST_ROOT" add README.md .gitignore
  git -C "$TEST_ROOT" commit -qm seed
}

prepare() {
  run "$HELPER" prepare --task TUNE-0365 --repo "$TEST_ROOT"
}

write_archive() {
  mkdir -p "$TEST_ROOT/documentation/archive/framework"
  {
    printf '%s\n' '---'
    printf '%s\n' 'id: TUNE-0365'
    printf '%s\n' 'status: archived'
    printf '%s\n' 'archive_doc: documentation/archive/framework/archive-TUNE-0365.md'
    printf '%s\n' 'verification_outcome:'
    printf '%s\n' '  n_a: false'
    printf '%s\n' '---'
    printf '%s\n' '# Archive TUNE-0365 archive'
    printf '%s\n' '### Acceptance Criteria'
    printf '%s\n' 'pass'
    printf '%s\n' '### Operator Handoff'
    printf '%s\n' 'none'
    printf '%s\n' '### Related'
    printf '%s\n' 'none'
  } > "$TEST_ROOT/documentation/archive/framework/archive-TUNE-0365.md"
}

commit_archive() {
  run "$HELPER" commit --task TUNE-0365 --repo "$TEST_ROOT" \
    --archive documentation/archive/framework/archive-TUNE-0365.md
}

@test "skip is explicit, successful, and does not require a repository" {
  run "$HELPER" skip --task TUNE-0365
  [ "$status" -eq 0 ]
  [[ "$output" == *"disposition=skipped_disabled"* ]]
}

@test "prepare refuses a dirty or staged repository and captures a clean one privately" {
  printf 'foreign\n' > "$TEST_ROOT/foreign.txt"
  prepare
  [ "$status" -eq 1 ]
  [[ "$output" == *"disposition=refused_dirty"* ]]

  rm "$TEST_ROOT/foreign.txt"
  printf 'staged\n' > "$TEST_ROOT/staged.txt"
  git -C "$TEST_ROOT" add staged.txt
  prepare
  [ "$status" -eq 1 ]
  [[ "$output" == *"disposition=refused_staged"* ]]
  git -C "$TEST_ROOT" reset -q HEAD -- staged.txt
  rm "$TEST_ROOT/staged.txt"

  prepare
  [ "$status" -eq 0 ]
  [[ "$output" == *"phase=prepared state=captured"* ]]
  state="$TEST_ROOT/.git/datarim/archive-auto-commit/TUNE-0365.record"
  [ -f "$state" ]
  mode="$(stat -c %a "$state" 2>/dev/null || stat -f %Lp "$state")"
  [ "$mode" = 600 ]
  grep -q '^task-id: TUNE-0365$' "$state"
  grep -Eq '^head: [0-9a-f]{40,64}$' "$state"
  grep -Eq '^index-tree: [0-9a-f]{40,64}$' "$state"
}

@test "inherited Git routing cannot redirect the requested repository" {
  other="$BATS_TEST_TMPDIR/other"
  git init -q "$other"
  git -C "$other" config user.name "Other Test"
  git -C "$other" config user.email "other@example.invalid"
  printf 'other\n' > "$other/README.md"
  printf 'datarim/\n' > "$other/.gitignore"
  git -C "$other" add README.md .gitignore
  git -C "$other" commit -qm seed
  run env GIT_DIR="$other/.git" GIT_WORK_TREE="$TEST_ROOT" \
    "$HELPER" prepare --task TUNE-0365 --repo "$TEST_ROOT"
  [ "$status" -eq 0 ]
  [ -f "$TEST_ROOT/.git/datarim/archive-auto-commit/TUNE-0365.record" ]
  [ ! -e "$other/.git/datarim/archive-auto-commit/TUNE-0365.record" ]
}

@test "nonstandard index flags and external filter surfaces refuse before status" {
  git -C "$TEST_ROOT" update-index --assume-unchanged README.md
  prepare
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=nonstandard-index"* ]]
  git -C "$TEST_ROOT" update-index --no-assume-unchanged README.md

  git -C "$TEST_ROOT" update-index --split-index
  prepare
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=nonstandard-index"* ]]
  git -C "$TEST_ROOT" update-index --no-split-index

  printf '*.md filter=audit\n' > "$TEST_ROOT/.gitattributes"
  git -C "$TEST_ROOT" add .gitattributes
  git -C "$TEST_ROOT" commit -qm attributes
  git -C "$TEST_ROOT" config filter.audit.clean 'touch should-not-run'
  prepare
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=external-filter-surface"* ]]
  [ ! -e "$TEST_ROOT/should-not-run" ]
}

@test "global attributes filter surface refuses at prepare" {
  attributes="$BATS_TEST_TMPDIR/global-attributes"
  marker="$BATS_TEST_TMPDIR/filter-ran"
  printf '*.md filter=audit\n' > "$attributes"
  git -C "$TEST_ROOT" config core.attributesFile "$attributes"
  git -C "$TEST_ROOT" config filter.audit.clean "touch $marker"
  prepare
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=external-filter-surface"* ]]
  [ ! -e "$marker" ]
}

@test "default per-user attributes cannot execute a clean filter" {
  xdg_home="$BATS_TEST_TMPDIR/xdg"
  marker="$BATS_TEST_TMPDIR/default-filter-ran"
  mkdir -p "$xdg_home/git"
  printf '*.md filter=audit\n' > "$xdg_home/git/attributes"
  git -C "$TEST_ROOT" config filter.audit.clean "touch $marker"

  run env XDG_CONFIG_HOME="$xdg_home" \
    "$HELPER" prepare --task TUNE-0365 --repo "$TEST_ROOT"

  [ "$status" -eq 0 ] \
    && [[ "$output" == *"phase=prepared state=captured"* ]] \
    && [ ! -e "$marker" ]
}

@test "commit creates one local fixed-message commit containing only the archive" {
  prepare
  [ "$status" -eq 0 ]
  parent="$(git -C "$TEST_ROOT" rev-parse HEAD)"
  write_archive
  commit_archive
  [ "$status" -eq 0 ]
  [[ "$output" == *"disposition=committed"* ]]
  [ "$(git -C "$TEST_ROOT" rev-parse HEAD^)" = "$parent" ]
  [ "$(git -C "$TEST_ROOT" log -1 --format=%s)" = "chore(archive): record TUNE-0365" ]
  [ "$(git -C "$TEST_ROOT" diff-tree --no-commit-id --name-only -r HEAD)" = "documentation/archive/framework/archive-TUNE-0365.md" ]
  [ -z "$(git -C "$TEST_ROOT" status --porcelain)" ]
}

@test "commit admits an optional same-area final snapshot" {
  prepare
  write_archive
  mkdir -p "$TEST_ROOT/documentation/archive/framework/snapshots"
  {
    printf '%s\n' '---'
    printf '%s\n' 'task_id: TUNE-0365'
    printf '%s\n' 'artifact: stage-snapshot'
    printf '%s\n' 'schema_version: 1'
    printf '%s\n' 'stage: archive'
    printf '%s\n' '---'
    printf '%s\n' 'snapshot'
  } > "$TEST_ROOT/documentation/archive/framework/snapshots/TUNE-0365-final-stage.md"
  run "$HELPER" commit --task TUNE-0365 --repo "$TEST_ROOT" \
    --archive documentation/archive/framework/archive-TUNE-0365.md \
    --snapshot documentation/archive/framework/snapshots/TUNE-0365-final-stage.md
  [ "$status" -eq 0 ]
  [ "$(git -C "$TEST_ROOT" diff-tree --no-commit-id --name-only -r HEAD | sort | wc -l | tr -d ' ')" -eq 2 ]
}

@test "foreign change at finalization refuses without moving HEAD or index" {
  prepare
  write_archive
  printf 'foreign\n' > "$TEST_ROOT/foreign file.txt"
  before_head="$(git -C "$TEST_ROOT" rev-parse HEAD)"
  before_index="$(git -C "$TEST_ROOT" write-tree)"
  commit_archive
  [ "$status" -eq 1 ]
  [[ "$output" == *"disposition=refused_dirty"* ]]
  [ "$(git -C "$TEST_ROOT" rev-parse HEAD)" = "$before_head" ]
  [ "$(git -C "$TEST_ROOT" write-tree)" = "$before_index" ]
}

@test "NUL-safe status refuses tabs, newlines, leading dashes, and rename pairs" {
  for foreign in $'tab\tname' $'line\nname' '-leading-dash'; do
    prepare
    write_archive
    printf 'foreign\n' > "$TEST_ROOT/$foreign"
    commit_archive
    [ "$status" -eq 1 ]
    [[ "$output" == *"disposition=refused_dirty"* ]]
    rm -f -- "$TEST_ROOT/$foreign" "$TEST_ROOT/documentation/archive/framework/archive-TUNE-0365.md"
  done

  printf 'rename source\n' > "$TEST_ROOT/rename-source"
  git -C "$TEST_ROOT" add rename-source
  git -C "$TEST_ROOT" commit -qm 'rename fixture'
  prepare
  write_archive
  mv "$TEST_ROOT/rename-source" "$TEST_ROOT/rename-destination"
  commit_archive
  [ "$status" -eq 1 ]
  [[ "$output" == *"disposition=refused_dirty"* ]]
}

@test "malformed or weak-permission state fails closed" {
  prepare
  write_archive
  state="$TEST_ROOT/.git/datarim/archive-auto-commit/TUNE-0365.record"
  chmod 644 "$state"
  before="$(git -C "$TEST_ROOT" rev-parse HEAD)"
  commit_archive
  [ "$status" -eq 1 ]
  [[ "$output" == *"disposition=refused_manifest"* ]]
  [ "$(git -C "$TEST_ROOT" rev-parse HEAD)" = "$before" ]
}

@test "archive frontmatter requires a closing delimiter" {
  prepare
  write_archive
  awk 'NR != 7 { print }' "$TEST_ROOT/documentation/archive/framework/archive-TUNE-0365.md" \
    > "$BATS_TEST_TMPDIR/unclosed"
  mv "$BATS_TEST_TMPDIR/unclosed" "$TEST_ROOT/documentation/archive/framework/archive-TUNE-0365.md"
  commit_archive
  [ "$status" -eq 1 ]
  [[ "$output" == *"disposition=refused_manifest"* ]]
}

@test "ignored runtime mutations remain excluded while a visible tracked ledger refuses" {
  prepare
  write_archive
  mkdir -p "$TEST_ROOT/datarim/plans" "$TEST_ROOT/datarim/reflection"
  printf 'ledger\n' > "$TEST_ROOT/datarim/tasks.md"
  printf 'reflection\n' > "$TEST_ROOT/datarim/reflection/reflection-TUNE-0365.md"
  printf 'plan\n' > "$TEST_ROOT/datarim/plans/TUNE-0365-plan.md"
  commit_archive
  [ "$status" -eq 0 ]
  [ "$(git -C "$TEST_ROOT" diff-tree --no-commit-id --name-only -r HEAD)" = "documentation/archive/framework/archive-TUNE-0365.md" ]

  git -C "$TEST_ROOT" add -f datarim/tasks.md
  git -C "$TEST_ROOT" commit -qm 'track ledger fixture'
  prepare
  [ "$status" -eq 1 ]
  [[ "$output" == *"disposition=refused_manifest"* ]]
  [[ "$output" == *"reason=runtime-path-visible"* ]]
}

@test "wrong task, wrong area, shared ledger, traversal, and symlink candidates refuse" {
  prepare
  write_archive
  for candidate in \
    documentation/archive/framework/archive-TUNE-9999.md \
    documentation/archive/general/archive-TUNE-0365.md \
    datarim/tasks.md \
    ../archive-TUNE-0365.md; do
    run "$HELPER" commit --task TUNE-0365 --repo "$TEST_ROOT" --archive "$candidate"
    [ "$status" -eq 1 ]
    [[ "$output" == *"disposition=refused_manifest"* ]]
  done

  rm -f "$TEST_ROOT/documentation/archive/framework/archive-TUNE-0365.md"
  prepare
  ln -s "$TEST_ROOT/README.md" "$TEST_ROOT/documentation/archive/framework/archive-TUNE-0365.md"
  commit_archive
  [ "$status" -eq 1 ]
  [[ "$output" == *"disposition=refused_manifest"* ]]
}

@test "valid same-task archive in a noncanonical area refuses" {
  prepare
  write_archive
  mkdir -p "$TEST_ROOT/documentation/archive/general"
  mv "$TEST_ROOT/documentation/archive/framework/archive-TUNE-0365.md" \
    "$TEST_ROOT/documentation/archive/general/archive-TUNE-0365.md"
  awk '{gsub("documentation/archive/framework/archive-TUNE-0365.md", "documentation/archive/general/archive-TUNE-0365.md"); print}' \
    "$TEST_ROOT/documentation/archive/general/archive-TUNE-0365.md" > "$BATS_TEST_TMPDIR/wrong-area"
  mv "$BATS_TEST_TMPDIR/wrong-area" "$TEST_ROOT/documentation/archive/general/archive-TUNE-0365.md"
  before="$(git -C "$TEST_ROOT" rev-parse HEAD)"
  run "$HELPER" commit --task TUNE-0365 --repo "$TEST_ROOT" \
    --archive documentation/archive/general/archive-TUNE-0365.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"disposition=refused_manifest reason=invalid-path"* ]]
  [ "$(git -C "$TEST_ROOT" rev-parse HEAD)" = "$before" ]
}

@test "branch movement after prepare refuses by compare-and-swap policy" {
  prepare
  git -C "$TEST_ROOT" commit --allow-empty -qm concurrent
  moved="$(git -C "$TEST_ROOT" rev-parse HEAD)"
  write_archive
  commit_archive
  [ "$status" -eq 1 ]
  [[ "$output" == *"disposition=refused_race"* ]]
  [ "$(git -C "$TEST_ROOT" rev-parse HEAD)" = "$moved" ]
}

@test "foreign index lock is never removed" {
  prepare
  write_archive
  printf 'foreign lock\n' > "$TEST_ROOT/.git/index.lock"
  commit_archive
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=index-lock-busy"* ]]
  [ -f "$TEST_ROOT/.git/index.lock" ]
  [ "$(cat "$TEST_ROOT/.git/index.lock")" = 'foreign lock' ]
}

@test "foreign bytes appearing during commit object creation refuse before ref movement" {
  prepare
  write_archive
  before="$(git -C "$TEST_ROOT" rev-parse HEAD)"
  shim_dir="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$shim_dir"
  real_git="$(command -v git)"
  # shellcheck disable=SC2016 # The generated shim expands these variables at runtime.
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'for arg in "$@"; do'
    printf '%s\n' '  if [ "$arg" = commit-tree ]; then printf "foreign\\n" > "$INJECT_REPO/foreign.txt"; fi'
    printf '%s\n' 'done'
    printf 'exec %q "$@"\n' "$real_git"
  } > "$shim_dir/git"
  chmod +x "$shim_dir/git"
  run env PATH="$shim_dir:$PATH" INJECT_REPO="$TEST_ROOT" \
    "$HELPER" commit --task TUNE-0365 --repo "$TEST_ROOT" \
    --archive documentation/archive/framework/archive-TUNE-0365.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"disposition=refused_race"* ]]
  [ "$(git -C "$TEST_ROOT" rev-parse HEAD)" = "$before" ]
}

@test "same-tree index metadata race is refused and never overwritten" {
  prepare
  write_archive
  before="$(git -C "$TEST_ROOT" rev-parse HEAD)"
  shim_dir="$BATS_TEST_TMPDIR/index-race-bin"
  mkdir -p "$shim_dir"
  real_git="$(command -v git)"
  # shellcheck disable=SC2016 # The generated shim expands these variables at runtime.
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'for arg in "$@"; do'
    printf '%s\n' '  if [ "$arg" = commit-tree ]; then "$REAL_GIT" -C "$INJECT_REPO" update-index --assume-unchanged README.md; fi'
    printf '%s\n' 'done'
    printf '%s\n' 'exec "$REAL_GIT" "$@"'
  } > "$shim_dir/git"
  chmod +x "$shim_dir/git"
  run env PATH="$shim_dir:$PATH" REAL_GIT="$real_git" INJECT_REPO="$TEST_ROOT" \
    "$HELPER" commit --task TUNE-0365 --repo "$TEST_ROOT" \
    --archive documentation/archive/framework/archive-TUNE-0365.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=index-changed"* ]]
  [ "$(git -C "$TEST_ROOT" rev-parse HEAD)" = "$before" ]
  [[ "$(git -C "$TEST_ROOT" ls-files -v README.md)" == h* ]]
}

@test "hostile hooks and commit signing are not invoked" {
  hook_marker="$BATS_TEST_TMPDIR/hook-ran"
  mkdir -p "$TEST_ROOT/.git/hooks"
  for hook in post-commit reference-transaction; do
    printf '#!/bin/sh\ntouch %s\n' "$hook_marker" > "$TEST_ROOT/.git/hooks/$hook"
    chmod +x "$TEST_ROOT/.git/hooks/$hook"
  done
  git -C "$TEST_ROOT" config commit.gpgSign true
  prepare
  write_archive
  commit_archive
  [ "$status" -eq 0 ]
  [ ! -e "$hook_marker" ]
}

@test "missing Git identity returns a machine-readable integrity disposition" {
  prepare
  write_archive
  before="$(git -C "$TEST_ROOT" rev-parse HEAD)"
  run env GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME= GIT_AUTHOR_EMAIL= \
    GIT_COMMITTER_NAME= GIT_COMMITTER_EMAIL= \
    "$HELPER" commit --task TUNE-0365 --repo "$TEST_ROOT" \
    --archive documentation/archive/framework/archive-TUNE-0365.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"disposition=integrity_error"* ]]
  [[ "$output" == *"reason=commit-object-failed"* ]]
  [ "$(git -C "$TEST_ROOT" rev-parse HEAD)" = "$before" ]
}

@test "repeated finalization creates no empty commit" {
  prepare
  write_archive
  commit_archive
  [ "$status" -eq 0 ]
  head="$(git -C "$TEST_ROOT" rev-parse HEAD)"
  commit_archive
  [ "$status" -eq 0 ]
  [[ "$output" == *"disposition=already_clean"* ]]
  [ "$(git -C "$TEST_ROOT" rev-parse HEAD)" = "$head" ]
}

@test "journal resumes truthfully after ref movement but before index synchronization" {
  prepare
  write_archive
  old="$(git -C "$TEST_ROOT" rev-parse HEAD)"
  temp_index="$BATS_TEST_TMPDIR/recovery-index"
  GIT_INDEX_FILE="$temp_index" git -C "$TEST_ROOT" read-tree "$old"
  blob="$(git -C "$TEST_ROOT" hash-object -w --no-filters -- documentation/archive/framework/archive-TUNE-0365.md)"
  GIT_INDEX_FILE="$temp_index" git -C "$TEST_ROOT" update-index --add --cacheinfo \
    "100644,$blob,documentation/archive/framework/archive-TUNE-0365.md"
  tree="$(GIT_INDEX_FILE="$temp_index" git -C "$TEST_ROOT" write-tree)"
  new="$(printf 'chore(archive): record TUNE-0365\n\n' | git -C "$TEST_ROOT" commit-tree "$tree" -p "$old")"
  state="$TEST_ROOT/.git/datarim/archive-auto-commit/TUNE-0365.record"
  awk -v new="$new" -v tree="$tree" '
    /^phase: prepared$/ { print "phase: commit-created"; next }
    /^new-commit: none$/ { print "new-commit: " new; next }
    /^archive-path: none$/ { print "archive-path: documentation/archive/framework/archive-TUNE-0365.md"; next }
    /^new-tree: none$/ { print "new-tree: " tree; next }
    { print }
  ' "$state" > "$BATS_TEST_TMPDIR/state.next"
  mv "$BATS_TEST_TMPDIR/state.next" "$state"
  chmod 600 "$state"
  branch_ref="$(git -C "$TEST_ROOT" symbolic-ref HEAD)"
  git -C "$TEST_ROOT" update-ref "$branch_ref" "$new" "$old"
  lock_dir="$TEST_ROOT/.git/datarim/archive-auto-commit/TUNE-0365.lock"
  mkdir "$lock_dir"
  printf '99999999\n' > "$lock_dir/owner.pid"
  printf 'stale\n' > "$lock_dir/status"

  prepare
  [ "$status" -eq 0 ]
  [[ "$output" == *"phase=prepared state=recovery-ready"* ]]

  commit_archive
  [ "$status" -eq 0 ]
  [[ "$output" == *"disposition=committed"* ]]
  [[ "$output" == *"recovered=true"* ]]
  [ "$(git -C "$TEST_ROOT" write-tree)" = "$tree" ]
  [ -z "$(git -C "$TEST_ROOT" status --porcelain)" ]
  [ ! -e "$state" ]
}

@test "recovery refuses a same-tree index metadata race without erasing it" {
  prepare
  write_archive
  old="$(git -C "$TEST_ROOT" rev-parse HEAD)"
  temp_index="$BATS_TEST_TMPDIR/recovery-race-index"
  GIT_INDEX_FILE="$temp_index" git -C "$TEST_ROOT" read-tree "$old"
  blob="$(git -C "$TEST_ROOT" hash-object -w --no-filters -- documentation/archive/framework/archive-TUNE-0365.md)"
  GIT_INDEX_FILE="$temp_index" git -C "$TEST_ROOT" update-index --add --cacheinfo \
    "100644,$blob,documentation/archive/framework/archive-TUNE-0365.md"
  tree="$(GIT_INDEX_FILE="$temp_index" git -C "$TEST_ROOT" write-tree)"
  new="$(printf 'chore(archive): record TUNE-0365\n\n' | git -C "$TEST_ROOT" commit-tree "$tree" -p "$old")"
  state="$TEST_ROOT/.git/datarim/archive-auto-commit/TUNE-0365.record"
  awk -v new="$new" -v tree="$tree" '
    /^phase: prepared$/ { print "phase: commit-created"; next }
    /^new-commit: none$/ { print "new-commit: " new; next }
    /^archive-path: none$/ { print "archive-path: documentation/archive/framework/archive-TUNE-0365.md"; next }
    /^new-tree: none$/ { print "new-tree: " tree; next }
    { print }
  ' "$state" > "$BATS_TEST_TMPDIR/recovery-race-state"
  mv "$BATS_TEST_TMPDIR/recovery-race-state" "$state"
  chmod 600 "$state"
  branch_ref="$(git -C "$TEST_ROOT" symbolic-ref HEAD)"
  git -C "$TEST_ROOT" update-ref "$branch_ref" "$new" "$old"

  shim_dir="$BATS_TEST_TMPDIR/recovery-race-bin"
  marker="$BATS_TEST_TMPDIR/recovery-race-injected"
  mkdir -p "$shim_dir"
  real_git="$(command -v git)"
  # shellcheck disable=SC2016 # The generated shim expands these variables at runtime.
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'saw_update=0; saw_cacheinfo=0'
    printf '%s\n' 'for arg in "$@"; do'
    printf '%s\n' '  [ "$arg" = update-index ] && saw_update=1'
    printf '%s\n' '  [ "$arg" = --cacheinfo ] && saw_cacheinfo=1'
    printf '%s\n' 'done'
    printf '%s\n' 'if [ "$saw_update" = 1 ] && [ "$saw_cacheinfo" = 1 ] && [ ! -e "$INJECT_MARKER" ]; then'
    printf '%s\n' '  env -u GIT_INDEX_FILE "$REAL_GIT" -C "$INJECT_REPO" update-index --assume-unchanged README.md'
    printf '%s\n' '  : > "$INJECT_MARKER"'
    printf '%s\n' 'fi'
    printf '%s\n' 'exec "$REAL_GIT" "$@"'
  } > "$shim_dir/git"
  chmod +x "$shim_dir/git"

  run env PATH="$shim_dir:$PATH" REAL_GIT="$real_git" \
    INJECT_REPO="$TEST_ROOT" INJECT_MARKER="$marker" \
    "$HELPER" commit --task TUNE-0365 --repo "$TEST_ROOT" \
    --archive documentation/archive/framework/archive-TUNE-0365.md

  [ "$status" -eq 2 ] \
    && [[ "$output" == *"disposition=committed_recovery_required"* ]] \
    && [[ "$output" == *"reason=index-changed"* ]] \
    && [[ "$(git -C "$TEST_ROOT" ls-files -v README.md)" == h* ]]
}

@test "source contains no network, tag, release, version, or changelog mutation" {
  run bash -c 'grep -En "git (push|fetch|tag|remote)|VERSION|CHANGELOG|release" "$1"' _ "$HELPER"
  [ "$status" -eq 1 ]
}
