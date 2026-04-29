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
