#!/usr/bin/env bats
#
# Contract tests for dev-tools/classify-bats-failure-scope.sh.
#
# Each test builds a throwaway git repository in a fresh temp dir (git init +
# real commits — NOT git archive, so the .git probe is CI-faithful), commits
# into (or away from) a scope directory, and asserts the classifier's verdict:
#   * scope with ZERO task commits in range -> pre-existing (exit 0, foreign noise)
#   * scope WITH task commits in range      -> regression  (exit 1, real block)
#   * undeterminable git probe              -> exit 2 (fail-closed, never foreign)
#
# Synthetic task IDs only (ABCD-0001) — no real TUNE-XXXX literal in the suite.
#
# AC mapping:
#   foreign-noise scope -> pre-existing      -> AC-1 / AC-3 (wish avto-klassifikaciya-chuzhogo-shuma)
#   touched scope       -> regression/block  -> AC-2 / AC-3 (wish nastoyashchaya-regressiya-ne-maskiruetsya)
#   fail-closed unknown -> exit 2            -> AC-2 (do not mask via unknown)
#   no host / private ID in shipped helper   -> AC-4 (wish generic-english-only)

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/classify-bats-failure-scope.sh"
    REPO="$(mktemp -d -t bats-classify-XXXX)"
    git -C "$REPO" init --quiet
    git -C "$REPO" config user.email "test@example.com"
    git -C "$REPO" config user.name "Test"
    git -C "$REPO" config commit.gpgsign false
    # Baseline commit becomes the "base" the task branched from.
    mkdir -p "$REPO/skills/foo" "$REPO/agents"
    printf '# baseline skill\n' > "$REPO/skills/foo/SKILL.md"
    printf '# baseline agent\n' > "$REPO/agents/bar.md"
    git -C "$REPO" add -A
    git -C "$REPO" commit --quiet -m "ABCD-0001: baseline"
    BASE="$(git -C "$REPO" rev-parse HEAD)"
}

teardown() {
    rm -rf "$REPO"
}

commit_change() {
    # commit_change <relative-path> <content>
    local path="$1" content="$2"
    mkdir -p "$REPO/$(dirname "$path")"
    printf '%s\n' "$content" > "$REPO/$path"
    git -C "$REPO" add -A
    git -C "$REPO" commit --quiet -m "ABCD-0001: change $path"
}

@test "foreign noise: failing test scope had ZERO task commits -> pre-existing, exit 0" {
    # Task commits only into agents/; the failing regression test asserts skills/.
    commit_change "agents/baz.md" "task touched agents only"
    run bash "$SCRIPT" --repo "$REPO" --base "$BASE" --scope "skills"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pre-existing"* ]]
    [[ "$output" == *"skills"* ]]
}

@test "real regression: failing test scope DID receive task commits -> regression, exit 1" {
    # Task commits INTO skills/; the failing regression test asserts skills/.
    commit_change "skills/foo/SKILL.md" "task touched the skills scope"
    run bash "$SCRIPT" --repo "$REPO" --base "$BASE" --scope "skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"regression"* ]]
    [[ "$output" == *"skills"* ]]
}

@test "real regression is never masked by another clean scope (mixed -> exit 1)" {
    # One scope clean (no commits), one scope touched. Aggregate must block.
    commit_change "skills/foo/SKILL.md" "touched skills"
    run bash "$SCRIPT" --repo "$REPO" --base "$BASE" --scope "agents" --scope "skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"pre-existing"*"agents"* ]] || [[ "$output" == *"agents"* ]]
    [[ "$output" == *"regression"*"skills"* ]] || [[ "$output" == *"regression"* ]]
}

@test "all scopes clean -> exit 0 (auto-classify all as foreign noise)" {
    commit_change "docs/readme.md" "task touched docs only"
    run bash "$SCRIPT" --repo "$REPO" --base "$BASE" --scope "skills" --scope "agents"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pre-existing"*"skills"* ]] || [[ "$output" == *"skills"* ]]
}

@test "explicit --range is honoured (overrides --base)" {
    commit_change "skills/foo/SKILL.md" "touched skills"
    run bash "$SCRIPT" --repo "$REPO" --range "${BASE}..HEAD" --scope "skills"
    [ "$status" -eq 1 ]
    [[ "$output" == *"regression"* ]]
}

@test "--quiet suppresses the report but exit code carries the verdict (regression)" {
    commit_change "skills/foo/SKILL.md" "touched skills"
    run bash "$SCRIPT" --repo "$REPO" --base "$BASE" --scope "skills" --quiet
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "--quiet suppresses the report but exit code carries the verdict (pre-existing)" {
    commit_change "agents/baz.md" "touched agents only"
    run bash "$SCRIPT" --repo "$REPO" --base "$BASE" --scope "skills" --quiet
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "fail-closed: undeterminable range exits 2, never auto-classifies as foreign" {
    run bash "$SCRIPT" --repo "$REPO" --range "nonexistent-ref..HEAD" --scope "skills"
    [ "$status" -eq 2 ]
    [[ "$output" != *"pre-existing"* ]]
}

@test "fail-closed: unknown base ref exits 2" {
    run bash "$SCRIPT" --repo "$REPO" --base "no-such-ref" --scope "skills"
    [ "$status" -eq 2 ]
    [[ "$output" != *"pre-existing"* ]]
}

@test "usage error: no --scope given (exit 2)" {
    run bash "$SCRIPT" --repo "$REPO" --base "$BASE"
    [ "$status" -eq 2 ]
}

@test "usage error: unknown flag (exit 2)" {
    run bash "$SCRIPT" --bogus
    [ "$status" -eq 2 ]
}

@test "usage error: missing repo dir (exit 2)" {
    run bash "$SCRIPT" --repo "$REPO/does-not-exist" --base "$BASE" --scope "skills"
    [ "$status" -eq 2 ]
}

@test "shipped helper carries no host names or private TASK-IDs (generic / public-OSS)" {
    # AC-4: the shipped logic must be generic. Synthetic IDs may appear in tests
    # but NEVER in the helper itself.
    run grep -nE 'arcana-dev|aether|TUNE-[0-9]{4}|ABCD-[0-9]{4}' "$SCRIPT"
    [ "$status" -ne 0 ]
}
