#!/usr/bin/env bats
# release-gate.bats — fail-closed pre-publish gate chain.
# TDD-red first. Script path resolved in setup() (bash-pitfalls.md: avoid the
# top-level-source 1..0 false green). External gates (CI status, registry
# version lookup) are injected via env-var hooks so the test is deterministic
# and mocks only the edges, never the gate logic.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/release-gate.sh"
    REPO="$(mktemp -d)"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email t@example.com
    git -C "$REPO" config user.name tester
    git -C "$REPO" config commit.gpgsign false
    git -C "$REPO" config tag.gpgsign false
    git -C "$REPO" branch -m main
    # Manifest version starts at the release target 0.6.4 — i.e. the realistic
    # post-bump state the gate expects (G0 version-assert). Tests that exercise a
    # different --version flip the manifest via _set_manifest_version.
    echo "0.6.4" > "$REPO/VERSION"
    # A signed-pipeline marker the gate greps for (G3).
    mkdir -p "$REPO/.github/workflows"
    printf 'jobs:\n  release:\n    steps:\n      - uses: actions/attest-build-provenance@x\n' \
        > "$REPO/.github/workflows/release.yml"
    git -C "$REPO" add -A
    git -C "$REPO" commit -q -m "fix: a patch-worthy change"
    git -C "$REPO" tag v0.6.3
    git -C "$REPO" commit -q --allow-empty -m "fix: another small fix"
    # All gates green by default; individual tests flip one red.
    export GATE_CI_STATUS=success          # G1
    export GATE_QA_VERDICT=ALL_PASS        # G2
    export GATE_VERSION_PUBLISHED=false    # G5
    export GATE_SMOKE_STATUS=success       # G7
    AUDIT_DIR="$REPO/docs/release-audit"
    export GATE_AUDIT_DIR="$AUDIT_DIR"
}

teardown() { rm -rf "$REPO"; }

_run_gate() { run "$SCRIPT" --repo "$REPO" --version "${1:-0.6.4}" --registry pypi "${@:2}"; }
_tag_exists() { git -C "$REPO" tag -l "v${1}" | grep -q "v${1}"; }
_set_manifest_version() { echo "$1" > "$REPO/VERSION"; }

@test "all gates green + patch bump -> tag created, exit 0, audit record written" {
    _run_gate 0.6.4
    [ "$status" -eq 0 ]
    _tag_exists 0.6.4
    [ -d "$AUDIT_DIR" ]
    run grep -rl "0.6.4" "$AUDIT_DIR"
    [ "$status" -eq 0 ]
}

@test "created tag is ANNOTATED (carries the stamped bump_level)" {
    _run_gate 0.6.4
    [ "$status" -eq 0 ]
    run git -C "$REPO" for-each-ref "refs/tags/v0.6.4" --format='%(contents)'
    echo "$output" | grep -qE '^bump_level=patch$'
    # objecttype of an annotated tag is "tag", lightweight is "commit".
    run git -C "$REPO" for-each-ref "refs/tags/v0.6.4" --format='%(objecttype)'
    [ "$output" = "tag" ]
}

@test "G1 red (CI failing) -> exit 1, NO tag" {
    GATE_CI_STATUS=failure _run_gate 0.6.4
    [ "$status" -eq 1 ]
    ! _tag_exists 0.6.4
}

@test "G2 red (QA not ALL_PASS) -> exit 1, NO tag" {
    GATE_QA_VERDICT=BLOCKED _run_gate 0.6.4
    [ "$status" -eq 1 ]
    ! _tag_exists 0.6.4
}

@test "G3 red (no signed pipeline) -> exit 1, NO tag" {
    rm -f "$REPO/.github/workflows/release.yml"
    _run_gate 0.6.4
    [ "$status" -eq 1 ]
    ! _tag_exists 0.6.4
}

@test "G4 red (not on main) -> exit 1, NO tag" {
    git -C "$REPO" checkout -q -b feature/x
    _run_gate 0.6.4
    [ "$status" -eq 1 ]
    ! _tag_exists 0.6.4
}

@test "G5 red (version already published) -> exit 1, NO tag" {
    GATE_VERSION_PUBLISHED=true _run_gate 0.6.4
    [ "$status" -eq 1 ]
    ! _tag_exists 0.6.4
}

@test "G6 escalate (major bump) -> exit 10, NO tag, no audit on escalate" {
    git -C "$REPO" commit -q --allow-empty -m "feat!: breaking redesign"
    _run_gate 1.0.0
    [ "$status" -eq 10 ]
    ! _tag_exists 1.0.0
}

@test "G7 post-publish smoke failure -> nonzero exit AFTER tag (operator rolls back)" {
    GATE_SMOKE_STATUS=failure _run_gate 0.6.4
    # tag is created (publish already happened); the script signals smoke-fail.
    _tag_exists 0.6.4
    [ "$status" -ne 0 ]
}

@test "dry-run never creates a tag even when all green" {
    _run_gate 0.6.4 --dry-run
    [ "$status" -eq 0 ]
    ! _tag_exists 0.6.4
}

@test "invalid version arg (not X.Y.Z) exits 2" {
    run "$SCRIPT" --repo "$REPO" --version "not-a-version" --registry pypi
    [ "$status" -eq 2 ]
}

@test "missing --repo exits 2" {
    run "$SCRIPT" --version 0.6.4 --registry pypi
    [ "$status" -eq 2 ]
}

@test "G0 manifest version != --version -> exit 1, NO tag, clear message (the dogfood loop)" {
    _set_manifest_version 0.6.3        # manifest stale, requesting 0.6.4
    _run_gate 0.6.4
    [ "$status" -eq 1 ]
    ! _tag_exists 0.6.4
    echo "$output" | grep -qiE "version mismatch|bump .*pyproject|manifest"
}

@test "G0 fires BEFORE the tag side-effect (no tag on mismatch even with all gates green)" {
    _set_manifest_version 0.5.0
    _run_gate 0.6.4
    [ "$status" -eq 1 ]
    ! _tag_exists 0.6.4
    [ ! -d "$AUDIT_DIR" ] || ! grep -rq "0.6.4" "$AUDIT_DIR"   # no audit record either
}

@test "G0 reads pyproject.toml when present (takes precedence over VERSION)" {
    printf '[project]\nname = "x"\nversion = "0.6.4"\n' > "$REPO/pyproject.toml"
    _set_manifest_version 0.1.0         # VERSION stale, but pyproject matches
    _run_gate 0.6.4
    [ "$status" -eq 0 ]
    _tag_exists 0.6.4
}

@test "G0 passes when manifest matches --version (normal post-bump path)" {
    _set_manifest_version 0.6.4
    _run_gate 0.6.4
    [ "$status" -eq 0 ]
    _tag_exists 0.6.4
}
