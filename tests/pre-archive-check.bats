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
