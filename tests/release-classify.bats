#!/usr/bin/env bats
# release-classify.bats — SemVer bump classifier (Conventional Commits + optional API-diff override).
# TDD-red first: the script under test does not exist yet. Per bash-pitfalls.md, the
# script path is resolved inside setup() (NOT sourced at top level) so a missing
# script fails each test visibly instead of zeroing the test count to a false 1..0.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/release-classify.sh"
    REPO="$(mktemp -d)"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email t@example.com
    git -C "$REPO" config user.name tester
    git -C "$REPO" config commit.gpgsign false
    git -C "$REPO" config tag.gpgsign false
    # A 0.x version source so zero_x logic is exercised (mirrors the coworker
    # donor at 0.6.3 — fixtures §2). Override per-test for a >=1.0.0 case.
    echo "0.6.3" > "$REPO/VERSION"
    git -C "$REPO" add VERSION
    # Seed: an initial tagged commit so the classifier has a `from` baseline.
    git -C "$REPO" commit -q -m "chore: seed"
    git -C "$REPO" tag v0.6.3
}

teardown() {
    rm -rf "$REPO"
}

# Helper: commit a subject then classify HEAD..last-tag range and echo bump_level.
_commit() { git -C "$REPO" commit -q --allow-empty -m "$1"; }
_classify_field() {
    # $1 = key (bump_level|api_diff|zero_x|escalate)
    run "$SCRIPT" --repo "$REPO" --api-diff off
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | sed -n "s/^$1=//p" | head -1
}

@test "fix: commit classifies as patch" {
    _commit "fix: tolerate prerelease tags"
    [ "$(_classify_field bump_level)" = "patch" ]
}

@test "feat: commit classifies as minor" {
    _commit "feat: add --append flag"
    [ "$(_classify_field bump_level)" = "minor" ]
}

@test "feat!: bang commit classifies as major" {
    _commit "feat!: drop python 3.8 support"
    [ "$(_classify_field bump_level)" = "major" ]
}

@test "BREAKING CHANGE: footer classifies as major (overrides fix: prefix)" {
    _commit "$(printf 'fix: refactor loader\n\nBREAKING CHANGE: drops the legacy config path')"
    [ "$(_classify_field bump_level)" = "major" ]
}

@test "chore + docs only classifies as none (nothing to release)" {
    _commit "chore: bump dev dep"
    _commit "docs: refresh readme"
    [ "$(_classify_field bump_level)" = "none" ]
}

@test "mixed fix + feat classifies as minor (highest wins)" {
    _commit "fix: small bug"
    _commit "feat: new surface"
    [ "$(_classify_field bump_level)" = "minor" ]
}

@test "version below 1.0.0 sets zero_x=true" {
    _commit "fix: x"
    [ "$(_classify_field zero_x)" = "true" ]
}

@test "version >= 1.0.0 sets zero_x=false" {
    echo "1.2.0" > "$REPO/VERSION"
    git -C "$REPO" commit -q -am "fix: bump version source to stable"
    [ "$(_classify_field zero_x)" = "false" ]
}

@test "0.x breaking change sets escalate=true even though arithmetic is not major" {
    # Under 0.x, a BREAKING CHANGE must escalate (operator decision, PRD 0.x).
    _commit "$(printf 'feat: redesign api\n\nBREAKING CHANGE: removes old entrypoint')"
    [ "$(_classify_field escalate)" = "true" ]
}

@test "major bump always sets escalate=true regardless of version" {
    _commit "feat!: breaking redesign"
    [ "$(_classify_field escalate)" = "true" ]
}

@test "patch under 0.x is autonomous: escalate=false" {
    _commit "fix: small fix"
    [ "$(_classify_field escalate)" = "false" ]
}

@test "api-diff off yields api_diff=unavailable (tool not consulted)" {
    _commit "fix: x"
    [ "$(_classify_field api_diff)" = "unavailable" ]
}

@test "--stamp emits bump_level / escalate / rationale lines for the tag message" {
    _commit "fix: stampable change"
    run "$SCRIPT" --repo "$REPO" --api-diff off --stamp
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^bump_level=patch$'
    echo "$output" | grep -qE '^escalate=false$'
    echo "$output" | grep -qE '^rationale='
}

@test "--test self-runs embedded fixtures and exits 0" {
    run "$SCRIPT" --test
    [ "$status" -eq 0 ]
}

@test "no commits since last tag yields bump_level=none" {
    # HEAD is exactly the tagged commit — empty range.
    [ "$(_classify_field bump_level)" = "none" ]
}

@test "usage error on missing --repo exits 2" {
    run "$SCRIPT" --api-diff off
    [ "$status" -eq 2 ]
}
