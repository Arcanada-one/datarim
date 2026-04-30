#!/usr/bin/env bats
#
# Tests for scripts/pre-archive-check.sh
#
# Contract under test (from commands/dr-archive.md, step 0 — TUNE-0003 Proposal 1):
#   For every git repository touched by a task, `/dr-archive` must block when
#   `git status --porcelain` is non-empty, listing every dirty repo so the
#   operator can choose commit / accept / abort.
#
# These tests verify the detection half of that contract (listing dirty repos,
# exit codes, multi-repo support). The interactive 3-way prompt is tested by
# archive-contract-lint.bats as a spec-regression assertion.
#
# Scenarios covered:
#   - AC-2.1 clean git   → exit 0 (baseline)
#   - AC-2.2 dirty primary repo → exit 1 + path listed
#   - AC-2.3 dirty secondary repo (task touches 2+ repos) → exit 1 + path listed
#   - edge  both repos dirty → exit 1 + both listed
#   - edge  untracked files count as dirty
#   - edge  staged-but-uncommitted counts as dirty
#   - edge  path not a git repo → exit 2
#   - edge  path does not exist → exit 2
#   - edge  no arguments → exit 2
#
# Tmpdir isolation: every test creates its own fake repo(s) in BATS_TEST_TMPDIR.
# No real repos are touched.

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/pre-archive-check.sh"

# Helper: create an initialized git repo at PATH with an initial commit.
make_clean_repo() {
    local repo="$1"
    mkdir -p "$repo"
    git -C "$repo" init --quiet --initial-branch=main
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test"
    echo "seed" > "$repo/README.md"
    git -C "$repo" add README.md
    git -C "$repo" commit --quiet -m "initial"
}

# Helper: make repo dirty by adding an untracked file (unless mode overrides).
make_dirty() {
    local repo="$1"
    local mode="${2:-untracked}"
    case "$mode" in
        untracked)  echo "scratch" > "$repo/scratch.txt" ;;
        modified)   echo "changed" >> "$repo/README.md" ;;
        staged)     echo "new" > "$repo/new.txt" && git -C "$repo" add new.txt ;;
    esac
}

# ---------- AC-2.1 baseline ----------

@test "clean git in single repo → exit 0 (baseline)" {
    make_clean_repo "$BATS_TEST_TMPDIR/repo1"
    run "$SCRIPT" "$BATS_TEST_TMPDIR/repo1"
    [ "$status" -eq 0 ]
}

@test "clean git in two repos → exit 0" {
    make_clean_repo "$BATS_TEST_TMPDIR/repo1"
    make_clean_repo "$BATS_TEST_TMPDIR/repo2"
    run "$SCRIPT" "$BATS_TEST_TMPDIR/repo1" "$BATS_TEST_TMPDIR/repo2"
    [ "$status" -eq 0 ]
}

# ---------- AC-2.2 dirty primary ----------

@test "dirty primary repo → exit 1 and path listed on stdout" {
    make_clean_repo "$BATS_TEST_TMPDIR/primary"
    make_dirty "$BATS_TEST_TMPDIR/primary" untracked
    run "$SCRIPT" "$BATS_TEST_TMPDIR/primary"
    [ "$status" -eq 1 ]
    [[ "$output" == *"primary"* ]]
}

@test "dirty primary repo → stderr contains 3-way prompt language" {
    make_clean_repo "$BATS_TEST_TMPDIR/primary"
    make_dirty "$BATS_TEST_TMPDIR/primary" untracked
    run "$SCRIPT" "$BATS_TEST_TMPDIR/primary"
    [ "$status" -eq 1 ]
    # Stderr is merged into $output by bats; assert all three options are mentioned.
    [[ "$output" == *"Commit now"* ]]
    [[ "$output" == *"accept pending state"* ]] || [[ "$output" == *"Accept"* ]]
    [[ "$output" == *"Abort"* ]]
}

# ---------- AC-2.3 dirty secondary (multi-repo) ----------

@test "clean primary + dirty secondary → exit 1 and only secondary on stdout" {
    make_clean_repo "$BATS_TEST_TMPDIR/primary"
    make_clean_repo "$BATS_TEST_TMPDIR/secondary"
    make_dirty "$BATS_TEST_TMPDIR/secondary" untracked
    # Capture stdout only (stderr stripped) for exact assertion
    run bash -c "'$SCRIPT' '$BATS_TEST_TMPDIR/primary' '$BATS_TEST_TMPDIR/secondary' 2>/dev/null"
    [ "$status" -eq 1 ]
    # Exactly one line on stdout: the dirty repo path
    [ "$(echo "$output" | wc -l | tr -d ' ')" = "1" ]
    [[ "$output" == *"secondary"* ]]
    [[ "$output" != *"primary"* ]]
}

# ---------- multi-dirty edge ----------

@test "both repos dirty → exit 1 and both paths listed" {
    make_clean_repo "$BATS_TEST_TMPDIR/a"
    make_clean_repo "$BATS_TEST_TMPDIR/b"
    make_dirty "$BATS_TEST_TMPDIR/a" untracked
    make_dirty "$BATS_TEST_TMPDIR/b" modified
    run "$SCRIPT" "$BATS_TEST_TMPDIR/a" "$BATS_TEST_TMPDIR/b"
    [ "$status" -eq 1 ]
    [[ "$output" == *"/a"* ]]
    [[ "$output" == *"/b"* ]]
}

# ---------- dirty variants ----------

@test "staged-but-uncommitted counts as dirty" {
    make_clean_repo "$BATS_TEST_TMPDIR/repo"
    make_dirty "$BATS_TEST_TMPDIR/repo" staged
    run "$SCRIPT" "$BATS_TEST_TMPDIR/repo"
    [ "$status" -eq 1 ]
}

@test "modified tracked file counts as dirty" {
    make_clean_repo "$BATS_TEST_TMPDIR/repo"
    make_dirty "$BATS_TEST_TMPDIR/repo" modified
    run "$SCRIPT" "$BATS_TEST_TMPDIR/repo"
    [ "$status" -eq 1 ]
}

# ---------- usage errors ----------

@test "no arguments → exit 2 with usage message" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage"* ]]
}

@test "non-existent path → exit 2" {
    run "$SCRIPT" "$BATS_TEST_TMPDIR/does-not-exist"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"does not exist"* ]]
}

@test "path exists but is not a git repo → exit 2" {
    mkdir -p "$BATS_TEST_TMPDIR/plain"
    echo "hello" > "$BATS_TEST_TMPDIR/plain/file.txt"
    run "$SCRIPT" "$BATS_TEST_TMPDIR/plain"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not a git repo"* ]] || [[ "$output" == *"not a git repository"* ]]
}

# ---------- stdout/stderr separation ----------

@test "stdout contains only dirty paths (machine-readable)" {
    make_clean_repo "$BATS_TEST_TMPDIR/clean"
    make_clean_repo "$BATS_TEST_TMPDIR/dirty"
    make_dirty "$BATS_TEST_TMPDIR/dirty" untracked
    # Capture stdout only
    run bash -c "'$SCRIPT' '$BATS_TEST_TMPDIR/clean' '$BATS_TEST_TMPDIR/dirty' 2>/dev/null"
    [ "$status" -eq 1 ]
    # stdout should be exactly one line with the dirty path
    [ "$(echo "$output" | wc -l | tr -d ' ')" = "1" ]
    [[ "$output" == *"dirty"* ]]
    [[ "$output" != *"clean"* ]]
}

# ---------- TUNE-0044 shared-mode helpers ----------

# Helper: seed a tracked file in a clean repo, then mutate without staging.
make_workflow_file() {
    local repo="$1"; local file="$2"; local content="$3"
    mkdir -p "$(dirname "$repo/$file")"
    echo "$content" > "$repo/$file"
    git -C "$repo" add "$file"
    git -C "$repo" commit --quiet -m "seed $file"
}

modify_with_task_id() {
    local repo="$1"; local file="$2"; local task_id="$3"
    echo "added by $task_id: workflow update" >> "$repo/$file"
}

# ---------- TUNE-0044 shared-mode tests ----------

@test "shared mode: foreign hunks only → exit 0 (archive proceeds)" {
    make_clean_repo "$BATS_TEST_TMPDIR/ws"
    make_workflow_file "$BATS_TEST_TMPDIR/ws" "datarim/tasks.md" "# tasks"
    modify_with_task_id "$BATS_TEST_TMPDIR/ws" "datarim/tasks.md" "TRANS-0021"
    run "$SCRIPT" --task-id TUNE-0044 --shared "$BATS_TEST_TMPDIR/ws"
    [ "$status" -eq 0 ]
    [[ "$output" == *"foreign"* ]]
}

@test "shared mode: own-task-ID hunks → exit 1 (must commit)" {
    make_clean_repo "$BATS_TEST_TMPDIR/ws"
    make_workflow_file "$BATS_TEST_TMPDIR/ws" "datarim/tasks.md" "# tasks"
    modify_with_task_id "$BATS_TEST_TMPDIR/ws" "datarim/tasks.md" "TUNE-0044"
    run "$SCRIPT" --task-id TUNE-0044 --shared "$BATS_TEST_TMPDIR/ws"
    [ "$status" -eq 1 ]
    [[ "$output" == *"own"* ]]
}

@test "shared mode: mixed (own + foreign) hunks → exit 1 (must stage selectively)" {
    make_clean_repo "$BATS_TEST_TMPDIR/ws"
    make_workflow_file "$BATS_TEST_TMPDIR/ws" "datarim/progress.md" "# progress"
    {
        echo "TRANS-0021: workflow update"
        echo "TUNE-0044: workflow update"
    } >> "$BATS_TEST_TMPDIR/ws/datarim/progress.md"
    run "$SCRIPT" --task-id TUNE-0044 --shared "$BATS_TEST_TMPDIR/ws"
    [ "$status" -eq 1 ]
    [[ "$output" == *"mixed"* ]]
}

@test "shared mode: unattributed hunks → exit 1 (default-deny)" {
    make_clean_repo "$BATS_TEST_TMPDIR/ws"
    make_workflow_file "$BATS_TEST_TMPDIR/ws" "datarim/notes.md" "# notes"
    echo "ad-hoc edit, no task id" >> "$BATS_TEST_TMPDIR/ws/datarim/notes.md"
    run "$SCRIPT" --task-id TUNE-0044 --shared "$BATS_TEST_TMPDIR/ws"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unattributed"* ]]
}

@test "shared mode: invalid --task-id → exit 2" {
    make_clean_repo "$BATS_TEST_TMPDIR/ws"
    run "$SCRIPT" --task-id "not-an-id" --shared "$BATS_TEST_TMPDIR/ws"
    [ "$status" -eq 2 ]
}

@test "shared mode: missing --shared → exit 2" {
    run "$SCRIPT" --task-id TUNE-0044
    [ "$status" -eq 2 ]
}

@test "legacy mode (no --task-id) preserved: dirty repo still exit 1" {
    make_clean_repo "$BATS_TEST_TMPDIR/repo"
    make_dirty "$BATS_TEST_TMPDIR/repo" untracked
    run "$SCRIPT" "$BATS_TEST_TMPDIR/repo"
    [ "$status" -eq 1 ]
}

# ---------- TUNE-0056 conditional-shared (marker auto-detect) ----------

# Helper: install .datarim-shared marker file at repo root + commit.
make_marker_repo() {
    local repo="$1"
    make_clean_repo "$repo"
    cat > "$repo/.datarim-shared" <<'EOF'
# Datarim shared-workspace marker (TUNE-0056)
EOF
    git -C "$repo" add .datarim-shared
    git -C "$repo" commit --quiet -m "marker"
}

@test "conditional-shared: marker + --task-id + foreign hunks → exit 0 (auto-shared)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    make_workflow_file "$BATS_TEST_TMPDIR/fw" "skills/foo.md" "# foo"
    modify_with_task_id "$BATS_TEST_TMPDIR/fw" "skills/foo.md" "DEV-1210"
    run "$SCRIPT" --task-id TUNE-0056 "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"foreign"* ]]
}

@test "conditional-shared: marker absent + --task-id + dirty repo → legacy STOP exit 1" {
    make_clean_repo "$BATS_TEST_TMPDIR/proj"
    make_dirty "$BATS_TEST_TMPDIR/proj" untracked
    run "$SCRIPT" --task-id TUNE-0056 "$BATS_TEST_TMPDIR/proj"
    [ "$status" -eq 1 ]
}

@test "conditional-shared: marker + --task-id + own hunks → exit 1 with own classification" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    make_workflow_file "$BATS_TEST_TMPDIR/fw" "skills/foo.md" "# foo"
    modify_with_task_id "$BATS_TEST_TMPDIR/fw" "skills/foo.md" "TUNE-0056"
    run "$SCRIPT" --task-id TUNE-0056 "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 1 ]
    [[ "$output" == *"own"* ]]
}

# ---------- TUNE-0059 whitelist (version-bump basenames) ----------

# T23: VERSION-only edit + --task-id → klass=whitelisted, exit 0
@test "shared mode: whitelisted basename (VERSION) + --task-id → exit 0 (whitelisted)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    make_workflow_file "$BATS_TEST_TMPDIR/fw" "VERSION" "1.0.0"
    echo "1.0.1" > "$BATS_TEST_TMPDIR/fw/VERSION"
    run "$SCRIPT" --task-id TUNE-0059 "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"whitelisted"* ]]
}

# T24: --no-whitelist escape → VERSION classified as unattributed → exit 1
@test "shared mode: --no-whitelist escape + VERSION → exit 1 (unattributed restored)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    make_workflow_file "$BATS_TEST_TMPDIR/fw" "VERSION" "1.0.0"
    echo "1.0.1" > "$BATS_TEST_TMPDIR/fw/VERSION"
    run "$SCRIPT" --task-id TUNE-0059 --no-whitelist "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unattributed"* ]]
}

# T25: non-whitelisted basename without task-id → still unattributed (default-deny preserved)
@test "shared mode: non-whitelisted basename without task-id → exit 1 (default-deny preserved)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    make_workflow_file "$BATS_TEST_TMPDIR/fw" "random.txt" "seed"
    echo "ad-hoc edit" >> "$BATS_TEST_TMPDIR/fw/random.txt"
    run "$SCRIPT" --task-id TUNE-0059 "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unattributed"* ]]
}

# ---------- TUNE-0060 mine-by-elimination klass ----------
#
# Founding incident: TUNE-0059 archive — `code/datarim/CLAUDE.md` and
# `code/datarim/README.md` (committed body has many historical task IDs)
# version-bump 1.18.0→1.18.2 misclassified as `foreign` despite diff lines
# being clean. With `--task-id` set + actual diff-line IDs == ∅ + body IDs ≠ ∅,
# attribute to current task (operator declared --task-id, diff has nothing
# else to attribute it to). Untracked files (no diff at all) NOT eligible —
# they fall through to existing classification per safety guard.

# T26 hit: body has foreign IDs, diff lines clean (e.g., version bump on doc) → mine-by-elimination + exit 0
@test "shared mode: body has foreign IDs + diff lines clean → mine-by-elimination (exit 0)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    # Seed CLAUDE.md-shape file: body has foreign historical task IDs
    make_workflow_file "$BATS_TEST_TMPDIR/fw" "doc.md" "Reference DEV-1210 fix and LTM-0009 benchmark."
    # Modify with content that contains NO task IDs (e.g., version-line bump)
    echo "Updated for v1.18.3 release." >> "$BATS_TEST_TMPDIR/fw/doc.md"
    run "$SCRIPT" --task-id TUNE-0060 "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"mine-by-elimination"* ]]
}

# T27 escape: diff lines contain TASK_ID → own classification (TUNE-0068: body context no longer
# taints; only +/- diff lines count toward mixed/own gate). NOT mine-by-elimination.
@test "shared mode: diff lines contain only TASK_ID, body has foreign → own (not mixed; TUNE-0068)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    make_workflow_file "$BATS_TEST_TMPDIR/fw" "doc.md" "Reference DEV-1210 fix."
    # Diff line contains TUNE-0060 only; DEV-1210 lives in the unchanged body (hunk context).
    echo "TUNE-0060: my edit on this line." >> "$BATS_TEST_TMPDIR/fw/doc.md"
    run "$SCRIPT" --task-id TUNE-0060 "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 1 ]
    [[ "$output" == *"own"* ]]
    [[ "$output" != *"mine-by-elimination"* ]]
}

# T28 regression-guard: diff lines contain ONLY foreign IDs → genuine foreign (not mine-by-elimination)
@test "shared mode: diff lines contain foreign IDs → foreign (not mine-by-elimination)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    make_workflow_file "$BATS_TEST_TMPDIR/fw" "doc.md" "# doc"
    # Diff line itself contains TRANS-0021 — genuine foreign edit
    echo "TRANS-0021: foreign edit on this line." >> "$BATS_TEST_TMPDIR/fw/doc.md"
    run "$SCRIPT" --task-id TUNE-0060 "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"foreign"* ]]
    [[ "$output" != *"mine-by-elimination"* ]]
}

# ---------- TUNE-0061 env-var whitelist extension ----------
#
# Founding incident: TUNE-0060 self-dogfood — `Projects/Websites/datarim.club/
# config.php` is a legitimate Datarim public-surface version-bump file, but the
# basename `config.php` is project-specific and does not belong in the canonical
# hardcoded list shipped to all consumers. `DATARIM_PRE_ARCHIVE_WHITELIST`
# (colon-separated basenames) lets each consumer extend the whitelist for their
# own version-bump files without modifying the framework.

# T29: env-var hit (single basename) → klass=whitelisted, exit 0
@test "shared mode: env-var DATARIM_PRE_ARCHIVE_WHITELIST=config.php → whitelisted (exit 0)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    make_workflow_file "$BATS_TEST_TMPDIR/fw" "config.php" "<?php \$version = '1.0.0';"
    echo "<?php \$version = '1.0.1';" > "$BATS_TEST_TMPDIR/fw/config.php"
    DATARIM_PRE_ARCHIVE_WHITELIST="config.php" run "$SCRIPT" --task-id TUNE-0061 "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"whitelisted"* ]]
}

# T30: env-var colon-separated multi-basename split → all entries whitelisted
@test "shared mode: env-var colon-separated 'foo:bar:config.php' → config.php whitelisted (exit 0)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    make_workflow_file "$BATS_TEST_TMPDIR/fw" "config.php" "seed"
    echo "edit" > "$BATS_TEST_TMPDIR/fw/config.php"
    DATARIM_PRE_ARCHIVE_WHITELIST="foo:bar:config.php" run "$SCRIPT" --task-id TUNE-0061 "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"whitelisted"* ]]
}

# T31: --no-whitelist overrides env-var (strict default-deny preserved)
@test "shared mode: --no-whitelist overrides env-var → unattributed (exit 1)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    make_workflow_file "$BATS_TEST_TMPDIR/fw" "config.php" "seed"
    echo "edit" > "$BATS_TEST_TMPDIR/fw/config.php"
    DATARIM_PRE_ARCHIVE_WHITELIST="config.php" run "$SCRIPT" --task-id TUNE-0061 --no-whitelist "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unattributed"* ]]
}

# ---------- TUNE-0068 own/mixed gate uses diff lines only ----------
#
# Founding incident: TUNE-0055 + TUNE-0067 archives — workspace files
# (`tasks.md` / `activeContext.md` / `backlog.md` / `progress.md`) reported
# `mixed` with current TASK_ID listed, despite `git diff HEAD | grep -E
# '^[+-][^+-]' | grep -c <TASK_ID>` returning 0 (own ID lived only in the
# committed body or hunk-context, not in any actual diff line). Operator had
# to manually re-verify per CLAUDE.md rule 4. Fix: own/mixed gate considers
# only `^[+-][^+-]` diff lines (`diff_line_ids`); body/context IDs no longer
# trigger `mixed`.

# T33 regression-guard: markdown-bullet diff line `+- TASK_ID …` must classify
# as `own`. Founding incident: TUNE-0068 self-dogfood on workspace
# `activeContext.md` — the regex `^[+-][^+-]` rejected `+- **TUNE-0068**`
# because the second char (`-`) collided with the diff-marker filter, leaving
# `diff_line_ids` empty and routing the file to `mine-by-elimination` despite
# the diff clearly carrying the current TASK_ID.
@test "shared mode: added markdown-bullet line `+- TASK_ID …` → own (TUNE-0068)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    make_workflow_file "$BATS_TEST_TMPDIR/fw" "ctx.md" "## Active Tasks"
    # Append a markdown bullet whose content begins with `-` (the bullet dash).
    echo "- TUNE-0068: my new active task entry." >> "$BATS_TEST_TMPDIR/fw/ctx.md"
    run "$SCRIPT" --task-id TUNE-0068 "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 1 ]
    [[ "$output" == *"own"* ]]
    [[ "$output" != *"mine-by-elimination"* ]]
}

# T32 hit: foreign +/- line + own task ID only in unchanged body (hunk context) → foreign
@test "shared mode: foreign diff line + own TASK_ID only in hunk context → foreign (TUNE-0068)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    # Seed: committed body carries the current TASK_ID + a foreign baseline ID.
    make_workflow_file "$BATS_TEST_TMPDIR/fw" "doc.md" "Reference TUNE-0068 fix and DEV-1210 baseline."
    # Modify: append a line whose only ID is foreign (TRANS-0021). The current
    # TASK_ID lives only on an unchanged context line.
    echo "TRANS-0021: foreign edit on this line." >> "$BATS_TEST_TMPDIR/fw/doc.md"
    run "$SCRIPT" --task-id TUNE-0068 "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 0 ]
    [[ "$output" == *"foreign"* ]]
    [[ "$output" != *"mixed"* ]]
}

# ---------- TUNE-0071 schema-compliance gate ----------

# T34: compliant thin-index lines pass schema gate (clean repo + datarim/).
@test "schema-check: compliant tasks.md/backlog.md → exit 0 (TUNE-0071)" {
    make_clean_repo "$BATS_TEST_TMPDIR/ws"
    mkdir -p "$BATS_TEST_TMPDIR/ws/datarim"
    cat > "$BATS_TEST_TMPDIR/ws/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TUNE-0071 · in_progress · P1 · L3 · Index-Style Refactor → tasks/TUNE-0071-task-description.md
EOF
    cat > "$BATS_TEST_TMPDIR/ws/datarim/backlog.md" <<'EOF'
# Backlog

## Pending

- INFRA-0099 · pending · P2 · L2 · Sample Backlog Item → tasks/INFRA-0099-task-description.md
EOF
    git -C "$BATS_TEST_TMPDIR/ws" add datarim/
    git -C "$BATS_TEST_TMPDIR/ws" commit --quiet -m "seed datarim"
    run "$SCRIPT" "$BATS_TEST_TMPDIR/ws"
    [ "$status" -eq 0 ]
}

# T35: legacy block-style heading in tasks.md → schema-check blocks (exit 1).
@test "schema-check: legacy ### TASK-ID: heading flagged → exit 1 (TUNE-0071)" {
    make_clean_repo "$BATS_TEST_TMPDIR/ws"
    mkdir -p "$BATS_TEST_TMPDIR/ws/datarim"
    cat > "$BATS_TEST_TMPDIR/ws/datarim/tasks.md" <<'EOF'
# Tasks

### TUNE-0071: Index-Style Refactor

- Status: in_progress
- Priority: P1
EOF
    git -C "$BATS_TEST_TMPDIR/ws" add datarim/
    git -C "$BATS_TEST_TMPDIR/ws" commit --quiet -m "seed legacy"
    run "$SCRIPT" "$BATS_TEST_TMPDIR/ws"
    [ "$status" -eq 1 ]
    [[ "$output" == *"non-compliant"* ]] || [[ "$output" == *"dr-doctor"* ]]
}

# T36: --no-schema-check overrides the gate (in-flight migration escape).
@test "schema-check: --no-schema-check bypasses non-compliant lines → exit 0 (TUNE-0071)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    mkdir -p "$BATS_TEST_TMPDIR/fw/datarim"
    cat > "$BATS_TEST_TMPDIR/fw/datarim/tasks.md" <<'EOF'
# Tasks

### TUNE-0071: Legacy block-style entry

Description body without thin-index format.
EOF
    git -C "$BATS_TEST_TMPDIR/fw" add datarim/
    git -C "$BATS_TEST_TMPDIR/fw" commit --quiet -m "seed legacy in marker repo"
    # Without override → blocks
    run "$SCRIPT" --task-id TUNE-0071 --shared "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 1 ]
    # With override → passes
    run "$SCRIPT" --task-id TUNE-0071 --shared "$BATS_TEST_TMPDIR/fw" --no-schema-check
    [ "$status" -eq 0 ]
}

# ---------- TUNE-0071 v2 gates (1.19.1) ----------
# T37: forbidden-file gate detects backlog-archive.md presence.
@test "v2 gate: backlog-archive.md presence → exit 1 (TUNE-0071 v2)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    mkdir -p "$BATS_TEST_TMPDIR/fw/datarim"
    cat > "$BATS_TEST_TMPDIR/fw/datarim/tasks.md" <<'EOF'
# Tasks

## Active
EOF
    cat > "$BATS_TEST_TMPDIR/fw/datarim/backlog-archive.md" <<'EOF'
# Backlog Archive (legacy aggregated)

## Completed

### TUNE-0001: Legacy entry
EOF
    git -C "$BATS_TEST_TMPDIR/fw" add datarim/
    git -C "$BATS_TEST_TMPDIR/fw" commit --quiet -m "seed legacy backlog-archive"
    run "$SCRIPT" --task-id TUNE-0071 --shared "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 1 ]
    [[ "$output" == *"backlog-archive.md"* ]] || [[ "$stderr_output" == *"backlog-archive.md"* ]] || true
}

# T38: forbidden-file gate detects progress.md presence.
@test "v2 gate: progress.md presence → exit 1 (TUNE-0071 v2)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    mkdir -p "$BATS_TEST_TMPDIR/fw/datarim"
    cat > "$BATS_TEST_TMPDIR/fw/datarim/tasks.md" <<'EOF'
# Tasks

## Active
EOF
    cat > "$BATS_TEST_TMPDIR/fw/datarim/progress.md" <<'EOF'
# Progress (abolished)
EOF
    git -C "$BATS_TEST_TMPDIR/fw" add datarim/
    git -C "$BATS_TEST_TMPDIR/fw" commit --quiet -m "seed legacy progress.md"
    run "$SCRIPT" --task-id TUNE-0071 --shared "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 1 ]
}

# T39: forbidden-section gate detects ## Последние завершённые.
@test "v2 gate: activeContext.md § Последние завершённые → exit 1 (TUNE-0071 v2)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    mkdir -p "$BATS_TEST_TMPDIR/fw/datarim"
    cat > "$BATS_TEST_TMPDIR/fw/datarim/tasks.md" <<'EOF'
# Tasks

## Active
EOF
    cat > "$BATS_TEST_TMPDIR/fw/datarim/activeContext.md" <<'EOF'
# Active Context

## Active Tasks

## Последние завершённые

- 2026-04-30 · TUNE-0001 · Legacy → archive/
EOF
    git -C "$BATS_TEST_TMPDIR/fw" add datarim/
    git -C "$BATS_TEST_TMPDIR/fw" commit --quiet -m "seed legacy section"
    run "$SCRIPT" --task-id TUNE-0071 --shared "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 1 ]
}

# T40: activeContext.md § Active Tasks paragraph form → exit 1 (line-format).
@test "v2 gate: activeContext.md Active paragraph form → exit 1 (TUNE-0071 v2)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    mkdir -p "$BATS_TEST_TMPDIR/fw/datarim"
    cat > "$BATS_TEST_TMPDIR/fw/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TRANS-0001 · in_progress · P1 · L4 · Transcribator → tasks/TRANS-0001-task-description.md
EOF
    cat > "$BATS_TEST_TMPDIR/fw/datarim/activeContext.md" <<'EOF'
# Active Context

## Active Tasks

- **TRANS-0001** (in_progress, 2026-04-21) — Long paragraph format that violates v2 contract.
EOF
    git -C "$BATS_TEST_TMPDIR/fw" add datarim/
    git -C "$BATS_TEST_TMPDIR/fw" commit --quiet -m "seed paragraph active"
    run "$SCRIPT" --task-id TUNE-0071 --shared "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 1 ]
}

# T41: thin-compliant activeContext.md Active section → exit 0.
@test "v2 gate: activeContext.md Active thin → exit 0 (TUNE-0071 v2)" {
    make_marker_repo "$BATS_TEST_TMPDIR/fw"
    mkdir -p "$BATS_TEST_TMPDIR/fw/datarim"
    cat > "$BATS_TEST_TMPDIR/fw/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TRANS-0001 · in_progress · P1 · L4 · Transcribator → tasks/TRANS-0001-task-description.md
EOF
    cat > "$BATS_TEST_TMPDIR/fw/datarim/activeContext.md" <<'EOF'
# Active Context

## Active Tasks

- TRANS-0001 · in_progress · P1 · L4 · Transcribator → tasks/TRANS-0001-task-description.md
EOF
    git -C "$BATS_TEST_TMPDIR/fw" add datarim/
    git -C "$BATS_TEST_TMPDIR/fw" commit --quiet -m "seed thin active"
    run "$SCRIPT" --task-id TUNE-0071 --shared "$BATS_TEST_TMPDIR/fw"
    [ "$status" -eq 0 ]
}
