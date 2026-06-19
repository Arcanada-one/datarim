#!/usr/bin/env bats
#
# Contract tests for dev-tools/check-stale-runtime.sh.
#
# Each test builds a throwaway git repository in BATS_TEST_TMPDIR (git init +
# real commits — NOT git archive, so the .git probe is CI-faithful), changes a
# path in a second commit, runs the detector over HEAD~1..HEAD, and asserts the
# advisory fires (shipped script / shipped skill) or stays silent (non-shipped).
#
# Synthetic task IDs only (ABCD-0001) — no real TUNE-XXXX literal in the suite.
#
# AC mapping:
#   fires on shipped script change   -> AC-1 / AC-5 (wish edinyj-skript-detekcii)
#   fires on shipped skill change    -> AC-1 / AC-5
#   silent on non-shipped change     -> AC-1 / AC-5
#   advisory is infra-agnostic       -> AC-6 (wish infra-agnostic-public-oss)

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-stale-runtime.sh"
    REPO="$(mktemp -d -t bats-stale-XXXX)"
    git -C "$REPO" init --quiet
    git -C "$REPO" config user.email "test@example.com"
    git -C "$REPO" config user.name "Test"
    git -C "$REPO" config commit.gpgsign false
    # Baseline commit so HEAD~1 exists for the range.
    mkdir -p "$REPO/docs"
    printf 'baseline\n' > "$REPO/docs/readme.md"
    git -C "$REPO" add -A
    git -C "$REPO" commit --quiet -m "ABCD-0001: baseline"
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

@test "fires on a shipped script change (scripts/lib/*.sh)" {
    commit_change "scripts/lib/helper.sh" "echo hi"
    run bash "$SCRIPT" --repo "$REPO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"update your Datarim install"* ]]
}

@test "fires on a shipped skill change (skills/*/SKILL.md)" {
    commit_change "skills/foo/SKILL.md" "# Foo skill"
    run bash "$SCRIPT" --repo "$REPO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"update your Datarim install"* ]]
}

@test "silent on a non-shipped change (docs)" {
    commit_change "docs/readme.md" "updated baseline"
    run bash "$SCRIPT" --repo "$REPO"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "silent on a non-shipped script outside scripts/lib (dev-tools)" {
    commit_change "dev-tools/some-tool.sh" "echo nope"
    run bash "$SCRIPT" --repo "$REPO"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "silent on a top-level skill file that is not SKILL.md" {
    commit_change "skills/foo/README.md" "# not a skill body"
    run bash "$SCRIPT" --repo "$REPO"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "--quiet suppresses advisory text but exit stays 0" {
    commit_change "scripts/lib/helper.sh" "echo hi"
    run bash "$SCRIPT" --repo "$REPO" --quiet
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "explicit --range is honoured" {
    commit_change "scripts/lib/helper.sh" "echo hi"
    run bash "$SCRIPT" --repo "$REPO" --range "HEAD~1..HEAD"
    [ "$status" -eq 0 ]
    [[ "$output" == *"update your Datarim install"* ]]
}

@test "advisory is infra-agnostic — no host names or install command" {
    commit_change "scripts/lib/helper.sh" "echo hi"
    run bash "$SCRIPT" --repo "$REPO"
    [ "$status" -eq 0 ]
    [[ "$output" != *"arcana-dev"* ]]
    [[ "$output" != *"aether"* ]]
    [[ "$output" != *"install.sh"* ]]
}

@test "fail-open: bad range exits 3 without advisory" {
    run bash "$SCRIPT" --repo "$REPO" --range "nonexistent-ref..HEAD"
    [ "$status" -eq 3 ]
    [[ "$output" != *"update your Datarim install"* ]]
}

@test "usage error on unknown flag (exit 2)" {
    run bash "$SCRIPT" --bogus
    [ "$status" -eq 2 ]
}

@test "missing repo dir (exit 2)" {
    run bash "$SCRIPT" --repo "$REPO/does-not-exist"
    [ "$status" -eq 2 ]
}
