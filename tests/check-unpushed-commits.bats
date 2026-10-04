#!/usr/bin/env bats
#
# Contract tests for dev-tools/check-unpushed-commits.sh.
#
# Each test builds a throwaway git repository (or repositories) in
# BATS_TEST_TMPDIR, simulates the upstream tracking point via
# `git update-ref refs/remotes/origin/<branch>` and/or
# `git branch --set-upstream-to`, writes a minimal task-description
# fixture with the relevant `type:` frontmatter, runs the helper, and
# asserts `status` + the stdout token.
#
# IMPORTANT: bats `run` captures both stdout and stderr in $output.
# When testing token-only output use --quiet flag so only the token
# appears in $output.  When testing without --quiet, use substring
# checks ([[ "$output" == *"token"* ]]) not equality.
#
# V-AC mapping:
#   C1-C6  -> V-AC-1 (STOP gate fires on correct type set)
#   C7-C15 -> V-AC-3 (stack-agnostic, edge cases, flags)
#   C16    -> V-AC-2 (spec-lint: Step 0.12 prose contract in dr-archive.md)
#   C17-C20-> usage/shape guards

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-unpushed-commits.sh"
    WORK="$(mktemp -d -t bats-upush-XXXX)"
}

teardown() {
    rm -rf "$WORK"
}

# ---------------------------------------------------------------------------
# Helper: build a minimal git repo with one initial commit.
# Uses the system default branch name (main or master — whatever git init
# creates) to avoid hardcoding "master" which fails on modern git.
# ---------------------------------------------------------------------------

# make_repo <dir>
# Creates a git repo with one committed file (initial commit).
# Prints the default branch name to stdout.
make_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email "test@example.com"
    git -C "$dir" config user.name "Test"
    echo "init" > "$dir/README.md"
    git -C "$dir" add README.md
    git -C "$dir" commit -q -m "init"
    git -C "$dir" symbolic-ref --short HEAD
}

# make_task_description <file> <type>
# Writes a minimal YAML-frontmatter task description.
make_task_description() {
    local file="$1"
    local type="$2"
    cat > "$file" <<EOF
---
task_id: FAKE-0001
title: 'test task'
status: in_progress
priority: P2
type: ${type}
---
# Test task
EOF
}

# set_upstream_tracking <repo_dir> <branch>
# Attaches a REAL bare remote at <dir>.origin.git, pushes the current branch to
# it, and sets upstream tracking via `git push -u`. This freezes
# refs/remotes/origin/<branch> at the pushed commit, so `@{u}..HEAD` counts only
# commits added AFTER this call — identical behaviour across git versions.
#
# A real bare remote is used deliberately instead of `update-ref` +
# branch.*.merge config: the latter leaves `@{u}` resolution dependent on
# git-version-specific handling of branch.<b>.merge=refs/heads/<b>, which made
# count drop to 0 on the CI git while passing locally. The push-based setup is
# version-stable.
set_upstream_tracking() {
    local dir="$1"
    local branch="$2"
    local bare="${dir}.origin.git"
    git init -q --bare "$bare"
    git -C "$dir" remote add origin "$bare"
    git -C "$dir" push -q -u origin "$branch"
}

# add_commit <repo_dir>
# Adds one more commit (simulating local work not yet pushed).
add_commit() {
    local dir="$1"
    echo "change-$$-$RANDOM" >> "$dir/file.txt"
    git -C "$dir" add file.txt
    git -C "$dir" commit -q -m "local change"
}

# ---------------------------------------------------------------------------
# V-AC-1: STOP gate fires on correct type set
# ---------------------------------------------------------------------------

@test "C1: count>0 + type:feature -> stop, status 0" {
    local repo="$WORK/repo1"
    local td="$WORK/task.md"
    local branch
    branch="$(make_repo "$repo")"
    set_upstream_tracking "$repo" "$branch"
    add_commit "$repo"
    make_task_description "$td" "feature"
    run "$SCRIPT" --repo "$repo" --task-description "$td" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "stop" ]
}

@test "C2: count>0 + type:bugfix -> stop" {
    local repo="$WORK/repo2"
    local td="$WORK/task.md"
    local branch
    branch="$(make_repo "$repo")"
    set_upstream_tracking "$repo" "$branch"
    add_commit "$repo"
    make_task_description "$td" "bugfix"
    run "$SCRIPT" --repo "$repo" --task-description "$td" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "stop" ]
}

@test "C3: count>0 + type:refactor -> stop" {
    local repo="$WORK/repo3"
    local td="$WORK/task.md"
    local branch
    branch="$(make_repo "$repo")"
    set_upstream_tracking "$repo" "$branch"
    add_commit "$repo"
    make_task_description "$td" "refactor"
    run "$SCRIPT" --repo "$repo" --task-description "$td" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "stop" ]
}

@test "C4: count==0 + type:feature -> clean" {
    local repo="$WORK/repo4"
    local td="$WORK/task.md"
    local branch
    branch="$(make_repo "$repo")"
    set_upstream_tracking "$repo" "$branch"
    # Do NOT add a commit -- HEAD == upstream
    make_task_description "$td" "feature"
    run "$SCRIPT" --repo "$repo" --task-description "$td" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "clean" ]
}

@test "C5: type:docs + count>0 -> advisory (not stop)" {
    local repo="$WORK/repo5"
    local td="$WORK/task.md"
    local branch
    branch="$(make_repo "$repo")"
    set_upstream_tracking "$repo" "$branch"
    add_commit "$repo"
    make_task_description "$td" "docs"
    run "$SCRIPT" --repo "$repo" --task-description "$td" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "advisory" ]
}

@test "C6: type:research + count>0 -> advisory (not stop)" {
    local repo="$WORK/repo6"
    local td="$WORK/task.md"
    local branch
    branch="$(make_repo "$repo")"
    set_upstream_tracking "$repo" "$branch"
    add_commit "$repo"
    make_task_description "$td" "research"
    run "$SCRIPT" --repo "$repo" --task-description "$td" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "advisory" ]
}

# ---------------------------------------------------------------------------
# V-AC-3: stack-agnostic + edge cases
# ---------------------------------------------------------------------------

@test "C7: base via @{u} upstream tracking (branch set-upstream-to) + 1 ahead -> stop" {
    local repo="$WORK/repo7"
    local td="$WORK/task.md"
    make_repo "$repo" >/dev/null
    # Create a feature branch
    git -C "$repo" checkout -q -b feature-branch
    local head_sha
    head_sha="$(git -C "$repo" rev-parse HEAD)"
    # Point origin/main at the current commit, set upstream
    git -C "$repo" update-ref "refs/remotes/origin/main" "$head_sha"
    git -C "$repo" config "branch.feature-branch.remote" "origin"
    git -C "$repo" config "branch.feature-branch.merge" "refs/heads/main"
    add_commit "$repo"
    make_task_description "$td" "feature"
    run "$SCRIPT" --repo "$repo" --task-description "$td" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "stop" ]
}

@test "C8: no upstream tracking, symbolic-ref non-main default (trunk) + 1 ahead -> stop" {
    local repo="$WORK/repo8"
    local td="$WORK/task.md"
    make_repo "$repo" >/dev/null
    # Simulate: origin HEAD points to trunk (not main)
    local head_sha
    head_sha="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" update-ref "refs/remotes/origin/trunk" "$head_sha"
    git -C "$repo" symbolic-ref "refs/remotes/origin/HEAD" "refs/remotes/origin/trunk"
    # No upstream tracking configured
    add_commit "$repo"
    make_task_description "$td" "feature"
    run "$SCRIPT" --repo "$repo" --task-description "$td" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "stop" ]
}

@test "C9: no upstream, no origin/HEAD symref -> last-resort origin/main + 1 ahead -> stop" {
    local repo="$WORK/repo9"
    local td="$WORK/task.md"
    make_repo "$repo" >/dev/null
    # Only provide origin/main (no upstream set, no symbolic-ref)
    local head_sha
    head_sha="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" update-ref "refs/remotes/origin/main" "$head_sha"
    # No branch upstream config, no symbolic-ref for origin/HEAD
    add_commit "$repo"
    make_task_description "$td" "feature"
    run "$SCRIPT" --repo "$repo" --task-description "$td" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "stop" ]
}

@test "C10: detached HEAD, no resolvable base -> clean + advisory stderr (fail-open)" {
    local repo="$WORK/repo10"
    local td="$WORK/task.md"
    make_repo "$repo" >/dev/null
    # Detach HEAD
    local head_sha
    head_sha="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" checkout -q --detach "$head_sha"
    make_task_description "$td" "feature"
    # Use --quiet so $output is only the token
    run "$SCRIPT" --repo "$repo" --task-description "$td" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "clean" ]
}

@test "C11: no origin remote at all -> clean + advisory" {
    local repo="$WORK/repo11"
    local td="$WORK/task.md"
    make_repo "$repo" >/dev/null
    # No remote added; no refs/remotes/*
    add_commit "$repo"
    make_task_description "$td" "feature"
    run "$SCRIPT" --repo "$repo" --task-description "$td" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "clean" ]
}

@test "C12: shallow clone -> advisory note on stderr, token still derived" {
    local src="$WORK/src-repo"
    local bare="$WORK/bare-repo.git"
    local shallow="$WORK/shallow-repo"
    local td="$WORK/task.md"
    # Create a source repo with 3 commits
    make_repo "$src" >/dev/null
    add_commit "$src"
    add_commit "$src"
    # Create bare clone
    git clone -q --bare "$src" "$bare"
    # Create shallow clone from bare (depth 1)
    git clone -q --depth 1 "file://$bare" "$shallow"
    git -C "$shallow" config user.email "test@example.com"
    git -C "$shallow" config user.name "Test"
    # Add one local commit not on remote
    add_commit "$shallow"
    make_task_description "$td" "feature"
    run "$SCRIPT" --repo "$shallow" --task-description "$td" --quiet
    [ "$status" -eq 0 ]
    # Token is stop, advisory, or clean (not exit 2 / usage error)
    [[ "$output" == "stop" || "$output" == "advisory" || "$output" == "clean" ]]
}

@test "C13: multi-repo - repo B (1 ahead + feature) fires stop independently" {
    local repoA="$WORK/repoA"
    local repoB="$WORK/repoB"
    local td="$WORK/task.md"
    local branchA branchB
    make_task_description "$td" "feature"

    # repo A is clean (count==0)
    branchA="$(make_repo "$repoA")"
    set_upstream_tracking "$repoA" "$branchA"
    run "$SCRIPT" --repo "$repoA" --task-description "$td" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "clean" ]

    # repo B has 1 unpushed commit
    branchB="$(make_repo "$repoB")"
    set_upstream_tracking "$repoB" "$branchB"
    add_commit "$repoB"
    run "$SCRIPT" --repo "$repoB" --task-description "$td" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "stop" ]
}

@test "C14: --quiet suppresses stderr rationale; stdout token unchanged" {
    local repo="$WORK/repo14"
    local td="$WORK/task.md"
    local branch
    branch="$(make_repo "$repo")"
    set_upstream_tracking "$repo" "$branch"
    add_commit "$repo"
    make_task_description "$td" "feature"
    # Without --quiet: bats captures stdout+stderr in $output; token + rationale mixed
    run "$SCRIPT" --repo "$repo" --task-description "$td"
    local full_output="$output"
    # With --quiet: only the token appears (no "gate:" rationale line)
    run "$SCRIPT" --repo "$repo" --task-description "$td" --quiet
    [ "$status" -eq 0 ]
    [ "$output" = "stop" ]
    [[ "$output" != *"gate:"* ]]
    # Without --quiet should have contained rationale
    [[ "$full_output" == *"gate:"* ]]
}

@test "C15: --help exits 0 and contains no stack-specific terms" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" != *"NestJS"* ]]
    [[ "$output" != *"Fastify"* ]]
    [[ "$output" != *"npm install"* ]]
}

# ---------------------------------------------------------------------------
# V-AC-2: Spec-lint -- Step 0.12 prose contract in dr-archive.md
# ---------------------------------------------------------------------------

@test "C16: dr-archive.md contains Step 0.12 block with three branch labels and Known Outstanding State" {
    local spec="$BATS_TEST_DIRNAME/../commands/dr-archive.md"
    [ -f "$spec" ]
    # Step 0.12 exists as a top-level step
    run grep -E "^0\.12\." "$spec"
    [ "$status" -eq 0 ]
    # check-unpushed-commits.sh is referenced
    run grep -F "check-unpushed-commits" "$spec"
    [ "$status" -eq 0 ]
    # Three named branches are present
    run grep -F "Push" "$spec"
    [ "$status" -eq 0 ]
    run grep -iE "Verify cherry" "$spec"
    [ "$status" -eq 0 ]
    run grep -iE "Accept loss" "$spec"
    [ "$status" -eq 0 ]
    # Known Outstanding State referenced in the spec
    run grep -F "Known Outstanding State" "$spec"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Usage / shape guards
# ---------------------------------------------------------------------------

@test "C17: missing --repo -> exit 2" {
    local td="$WORK/task.md"
    make_task_description "$td" "feature"
    run "$SCRIPT" --task-description "$td"
    [ "$status" -eq 2 ]
}

@test "C18: missing --task-description -> exit 2" {
    local repo="$WORK/repo18"
    make_repo "$repo" >/dev/null
    run "$SCRIPT" --repo "$repo"
    [ "$status" -eq 2 ]
}

@test "C19: --repo points at a non-git directory -> exit 2" {
    local non_git="$WORK/not-a-repo"
    local td="$WORK/task.md"
    mkdir -p "$non_git"
    make_task_description "$td" "feature"
    run "$SCRIPT" --repo "$non_git" --task-description "$td"
    [ "$status" -eq 2 ]
}

@test "C20: unknown flag -> exit 2" {
    local repo="$WORK/repo20"
    local td="$WORK/task.md"
    make_repo "$repo" >/dev/null
    make_task_description "$td" "feature"
    run "$SCRIPT" --repo "$repo" --task-description "$td" --bogus-flag
    [ "$status" -eq 2 ]
}
