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
_prepare_release_metadata() {
    local version="$1" category="$2" subject="$3"
    printf '%s\n' "$version" > "$REPO/VERSION"
    cat > "$REPO/CHANGELOG.md" <<EOF
# Changelog

## [Unreleased]

## [$version] — 2026-11-02

### $category

- Synthetic declaration for classifier coverage.
EOF
    git -C "$REPO" add VERSION CHANGELOG.md
    git -C "$REPO" commit -q -m "$subject"
}
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

@test "exact VERSION and Added changelog declaration classify a squash release as minor" {
    _prepare_release_metadata 0.7.0 Added "Datarim release 0.7.0"
    run "$SCRIPT" --repo "$REPO" --from v0.6.3 --to HEAD --api-diff off
    [ "$status" -eq 0 ] && [[ "$output" == *"bump_level=minor"* ]] &&
        [[ "$output" == *"release_metadata=minor"* ]] &&
        [[ "$output" == *"api_diff=unavailable"* ]]
}

@test "release metadata is read from the exact target tree" {
    _prepare_release_metadata 0.7.0 Added "Datarim release 0.7.0"
    printf '9.9.9\n' > "$REPO/VERSION"
    printf '# Unrelated working-tree changelog state\n' > "$REPO/CHANGELOG.md"
    run "$SCRIPT" --repo "$REPO" --from v0.6.3 --to HEAD --api-diff off
    [ "$status" -eq 0 ] && [[ "$output" == *"bump_level=minor"* ]] &&
        [[ "$output" == *"release_metadata=minor"* ]]
}

@test "Fixed changelog declaration is accepted only for the immediate patch version" {
    _prepare_release_metadata 0.6.4 Fixed "Datarim release 0.6.4"
    run "$SCRIPT" --repo "$REPO" --from v0.6.3 --to HEAD --api-diff auto
    [ "$status" -eq 0 ] && [[ "$output" == *"bump_level=patch"* ]] &&
        [[ "$output" == *"release_metadata=patch"* ]] &&
        [[ "$output" == *"api_diff=unavailable"* ]]
}

@test "VERSION alone cannot classify a non-Conventional range" {
    printf '0.7.0\n' > "$REPO/VERSION"
    cat > "$REPO/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

- No versioned release declaration.
EOF
    git -C "$REPO" add VERSION CHANGELOG.md
    git -C "$REPO" commit -q -m "Datarim release 0.7.0"
    run "$SCRIPT" --repo "$REPO" --from v0.6.3 --to HEAD --api-diff off
    [ "$status" -eq 0 ] && [[ "$output" == *"bump_level=none"* ]] &&
        [[ "$output" == *"release_metadata=none"* ]]
}

@test "mismatched VERSION transition cannot use an Added declaration" {
    _prepare_release_metadata 0.7.1 Added "Datarim release 0.7.1"
    run "$SCRIPT" --repo "$REPO" --from v0.6.3 --to HEAD --api-diff off
    [ "$status" -eq 0 ] && [[ "$output" == *"bump_level=none"* ]] &&
        [[ "$output" == *"release_metadata=none"* ]]
}

@test "ambiguous Changed changelog content does not infer a metadata bump" {
    _prepare_release_metadata 0.7.0 Changed "Datarim release 0.7.0"
    run "$SCRIPT" --repo "$REPO" --from v0.6.3 --to HEAD --api-diff off
    [ "$status" -eq 0 ] && [[ "$output" == *"bump_level=none"* ]] &&
        [[ "$output" == *"release_metadata=none"* ]]
}

@test "Conventional breaking marker remains major over a minor metadata declaration" {
    _prepare_release_metadata 0.7.0 Added "feat!: synthetic breaking declaration"
    run "$SCRIPT" --repo "$REPO" --from v0.6.3 --to HEAD --api-diff off
    [ "$status" -eq 0 ] && [[ "$output" == *"bump_level=major"* ]] &&
        [[ "$output" == *"release_metadata=minor"* ]] &&
        [[ "$output" == *"escalate=true"* ]]
}

@test "Breaking Changes changelog declaration classifies matching major transition" {
    _prepare_release_metadata 1.0.0 "Breaking Changes" "Datarim release 1.0.0"
    run "$SCRIPT" --repo "$REPO" --from v0.6.3 --to HEAD --api-diff auto
    [ "$status" -eq 0 ] && [[ "$output" == *"bump_level=major"* ]] &&
        [[ "$output" == *"release_metadata=major"* ]] &&
        [[ "$output" == *"escalate=true"* ]]
}

@test "usage error on missing --repo exits 2" {
    run "$SCRIPT" --api-diff off
    [ "$status" -eq 2 ]
}

@test "unresolved explicit baseline or target fails closed instead of no bump" {
    run "$SCRIPT" --repo "$REPO" --from v99.99.99 --api-diff off
    [ "$status" -eq 3 ]
    run "$SCRIPT" --repo "$REPO" --to missing-commit --api-diff off
    [ "$status" -eq 3 ]
}

@test "installed API tool without a computed diff remains unavailable" {
    _commit "fix: x"
    mkdir "$REPO/tools"
    printf '#!/bin/sh\nexit 0\n' > "$REPO/tools/griffe"
    chmod +x "$REPO/tools/griffe"
    run env PATH="$REPO/tools:$PATH" "$SCRIPT" --repo "$REPO" --api-diff auto
    [ "$status" -eq 0 ]
    [[ "$output" == *"api_diff=unavailable"* ]]
}

@test "invalid API-diff mode is refused" {
    run "$SCRIPT" --repo "$REPO" --api-diff invented
    [ "$status" -eq 2 ]
}
