#!/usr/bin/env bats
# Regression contract for dev-tools/check-runtime-drift.sh — a runtime symlinked
# into a feature-worktree (stale rules) must FAIL loudly; a main checkout, a
# release-tag pin, and copy-mode must PASS.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    GATE="$REPO_ROOT/dev-tools/check-runtime-drift.sh"
    WORK="$(mktemp -d "${BATS_TMPDIR}/drift.XXXXXX")"

    # Fixture framework checkout with the three runtime scopes.
    git init -q -b main "$WORK/framework"
    (
        cd "$WORK/framework"
        git config user.email t@example.invalid; git config user.name t
        mkdir -p skills commands agents
        echo "9.9.9" > VERSION
        touch skills/.keep commands/.keep agents/.keep
        git add -A && git commit -qm base
    )
    mkdir -p "$WORK/claude"
    for s in skills commands agents; do
        ln -s "$WORK/framework/$s" "$WORK/claude/$s"
    done
}

teardown() { rm -rf "$WORK"; }

@test "D1 PASS when the runtime resolves into a main checkout" {
    run bash "$GATE" --check --claude-dir "$WORK/claude"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULT: PASS"* ]]
}

@test "D2 FAIL when the checkout sits on a feature branch" {
    (cd "$WORK/framework" && git checkout -q -b fix/some-feature-worktree)
    run bash "$GATE" --check --claude-dir "$WORK/claude"
    [ "$status" -eq 1 ]
    [[ "$output" == *"runtime drift"*"fix/some-feature-worktree"* ]]
}

@test "D3 PASS when detached exactly on a v* release tag (tag-pinned deployment)" {
    (cd "$WORK/framework" && git tag -a v9.9.9 -m r && git checkout -q --detach v9.9.9)
    run bash "$GATE" --check --claude-dir "$WORK/claude"
    [ "$status" -eq 0 ]
}

@test "D4 FAIL when detached NOT on a release tag" {
    (cd "$WORK/framework" && git checkout -q --detach HEAD)
    run bash "$GATE" --check --claude-dir "$WORK/claude"
    [ "$status" -eq 1 ]
}

@test "D5 copy-mode (real directories) is skipped, not failed" {
    rm "$WORK/claude/skills" && mkdir "$WORK/claude/skills"
    (cd "$WORK/framework" && git checkout -q -b fix/other)   # other scopes still drift
    run bash "$GATE" --check --claude-dir "$WORK/claude"
    [ "$status" -eq 1 ]                                       # commands/agents still fail
    [[ "$output" == *"copy-mode"* ]]
    # All-copy-mode passes:
    for s in commands agents; do rm "$WORK/claude/$s" && mkdir "$WORK/claude/$s"; done
    run bash "$GATE" --check --claude-dir "$WORK/claude"
    [ "$status" -eq 0 ]
}

@test "D6 FAIL on mixed runtime (scopes resolving into different checkouts)" {
    git init -q -b main "$WORK/framework2"
    (cd "$WORK/framework2" && git config user.email t@e.invalid && git config user.name t && mkdir -p agents && echo 1.0.0 > VERSION && git add -A && git commit -qm b)
    rm "$WORK/claude/agents" && ln -s "$WORK/framework2/agents" "$WORK/claude/agents"
    run bash "$GATE" --check --claude-dir "$WORK/claude"
    [ "$status" -eq 1 ]
    [[ "$output" == *"mixed runtime"* ]]
}

@test "D7 broken symlink is a FAIL, and usage errors are exit 2" {
    rm "$WORK/claude/skills" && ln -s "$WORK/nonexistent" "$WORK/claude/skills"
    run bash "$GATE" --check --claude-dir "$WORK/claude"
    [ "$status" -eq 1 ]
    run bash "$GATE" --claude-dir "$WORK/claude"
    [ "$status" -eq 2 ]
    run bash "$GATE" --check --claude-dir "$WORK/no-such-dir"
    [ "$status" -eq 2 ]
}
