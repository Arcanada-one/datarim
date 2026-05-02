#!/usr/bin/env bats
#
# Tests for scripts/version-consistency-check.sh (TUNE-0080).
#
# Contract: when the framework's `VERSION` file changed in HEAD->working-tree,
# all consumer files (CLAUDE.md, README.md, docs/) must reference the new
# version. If any still cite the old version, archive is blocked.
#
# Scenarios:
#   T1 VERSION unchanged → exit 0 (skip — most archives don't bump)
#   T2 VERSION bumped + all consumers updated → exit 0
#   T3 VERSION bumped + lagging CLAUDE.md → exit 1, lagging file listed
#   T4 VERSION bumped + lagging README.md → exit 1, lagging file listed
#   T5 VERSION bumped + lagging docs/ file → exit 1
#   T6 --allow-version-lag overrides exit 1 → exit 0 with stderr warning
#   T7 not a git repo → exit 2
#   T8 missing VERSION file in HEAD (initial commit case) → exit 0 (no prior version)
#   T9 multi-line VERSION (whitespace tolerance) → handled correctly

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/version-consistency-check.sh"

# Helper: bootstrap a fake framework repo at REPO with VERSION = $2,
# CLAUDE.md citing $3, README.md citing $4. Initial commit captured.
seed_repo() {
    local repo="$1" old_ver="$2" claude_ver="$3" readme_ver="$4"
    mkdir -p "$repo/docs"
    git -C "$repo" init --quiet --initial-branch=main
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config user.name "Test"
    printf '%s\n' "$old_ver" > "$repo/VERSION"
    printf '> **Version:** %s\n' "$claude_ver" > "$repo/CLAUDE.md"
    printf '[![Version: %s](https://img.shields.io/badge/Version-%s-green.svg)](VERSION)\n' "$readme_ver" "$readme_ver" > "$repo/README.md"
    printf '# Evolution Log\n\nv%s landed.\n' "$claude_ver" > "$repo/docs/evolution-log.md"
    git -C "$repo" add -A
    git -C "$repo" commit --quiet -m "initial"
}

# Helper: bump VERSION file in working tree (uncommitted).
bump_version() {
    local repo="$1" new_ver="$2"
    printf '%s\n' "$new_ver" > "$repo/VERSION"
}

@test "T1: VERSION unchanged → exit 0 (skip)" {
    seed_repo "$BATS_TEST_TMPDIR/r" "1.0.0" "1.0.0" "1.0.0"
    run "$SCRIPT" "$BATS_TEST_TMPDIR/r"
    [ "$status" -eq 0 ]
}

@test "T2: VERSION bumped, all consumers updated → exit 0" {
    seed_repo "$BATS_TEST_TMPDIR/r" "1.0.0" "1.0.0" "1.0.0"
    bump_version "$BATS_TEST_TMPDIR/r" "1.1.0"
    # update consumers in working tree to match
    printf '> **Version:** 1.1.0\n' > "$BATS_TEST_TMPDIR/r/CLAUDE.md"
    printf '[![Version: 1.1.0](https://img.shields.io/badge/Version-1.1.0-green.svg)](VERSION)\n' > "$BATS_TEST_TMPDIR/r/README.md"
    printf '# Evolution Log\n\nv1.1.0 landed.\n' > "$BATS_TEST_TMPDIR/r/docs/evolution-log.md"
    run "$SCRIPT" "$BATS_TEST_TMPDIR/r"
    [ "$status" -eq 0 ]
}

@test "T3: VERSION bumped, CLAUDE.md still cites old → exit 1" {
    seed_repo "$BATS_TEST_TMPDIR/r" "1.0.0" "1.0.0" "1.0.0"
    bump_version "$BATS_TEST_TMPDIR/r" "1.1.0"
    # CLAUDE.md left at 1.0.0 (stale)
    run "$SCRIPT" "$BATS_TEST_TMPDIR/r"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CLAUDE.md"* ]]
    [[ "$output" == *"1.0.0"* ]]
}

@test "T4: VERSION bumped, README.md stale → exit 1" {
    seed_repo "$BATS_TEST_TMPDIR/r" "1.0.0" "1.0.0" "1.0.0"
    bump_version "$BATS_TEST_TMPDIR/r" "1.1.0"
    printf '> **Version:** 1.1.0\n' > "$BATS_TEST_TMPDIR/r/CLAUDE.md"
    # README.md left stale
    run "$SCRIPT" "$BATS_TEST_TMPDIR/r"
    [ "$status" -eq 1 ]
    [[ "$output" == *"README.md"* ]]
}

@test "T5: VERSION bumped, docs/ stale → exit 0 (docs/ is historical ledger, excluded by design)" {
    # Rationale: docs/evolution-log.md / docs/release-notes.md are append-only
    # historical surfaces. They reference past versions BY DESIGN. Including
    # them in the check would fire on every subsequent archive (every prior
    # release entry would match). The recurring drift class concerned
    # current-state surfaces only (CLAUDE.md "Version:" + README.md badge).
    seed_repo "$BATS_TEST_TMPDIR/r" "1.0.0" "1.0.0" "1.0.0"
    bump_version "$BATS_TEST_TMPDIR/r" "1.1.0"
    printf '> **Version:** 1.1.0\n' > "$BATS_TEST_TMPDIR/r/CLAUDE.md"
    printf '[![Version: 1.1.0](https://img.shields.io/badge/Version-1.1.0-green.svg)](VERSION)\n' > "$BATS_TEST_TMPDIR/r/README.md"
    # docs/ left at 1.0.0 — must NOT fail the gate
    run "$SCRIPT" "$BATS_TEST_TMPDIR/r"
    [ "$status" -eq 0 ]
}

@test "T6: --allow-version-lag overrides exit 1 → exit 0 with warning" {
    seed_repo "$BATS_TEST_TMPDIR/r" "1.0.0" "1.0.0" "1.0.0"
    bump_version "$BATS_TEST_TMPDIR/r" "1.1.0"
    # All consumers stale
    run "$SCRIPT" --allow-version-lag "$BATS_TEST_TMPDIR/r"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"* ]] || [[ "$output" == *"warning"* ]] || [[ "$output" == *"override"* ]]
}

@test "T7: not a git repo → exit 2" {
    mkdir -p "$BATS_TEST_TMPDIR/notrepo"
    run "$SCRIPT" "$BATS_TEST_TMPDIR/notrepo"
    [ "$status" -eq 2 ]
}

@test "T8: missing VERSION in HEAD (initial bootstrap) → exit 0" {
    mkdir -p "$BATS_TEST_TMPDIR/r"
    git -C "$BATS_TEST_TMPDIR/r" init --quiet --initial-branch=main
    git -C "$BATS_TEST_TMPDIR/r" config user.email "test@example.com"
    git -C "$BATS_TEST_TMPDIR/r" config user.name "Test"
    printf 'seed\n' > "$BATS_TEST_TMPDIR/r/README.md"
    git -C "$BATS_TEST_TMPDIR/r" add -A
    git -C "$BATS_TEST_TMPDIR/r" commit --quiet -m "initial"
    # Now add VERSION (no prior baseline)
    printf '1.0.0\n' > "$BATS_TEST_TMPDIR/r/VERSION"
    run "$SCRIPT" "$BATS_TEST_TMPDIR/r"
    [ "$status" -eq 0 ]
}

@test "T9: VERSION value tolerates trailing whitespace" {
    seed_repo "$BATS_TEST_TMPDIR/r" "1.0.0" "1.0.0" "1.0.0"
    # Bump with trailing whitespace
    printf '1.1.0  \n' > "$BATS_TEST_TMPDIR/r/VERSION"
    printf '> **Version:** 1.1.0\n' > "$BATS_TEST_TMPDIR/r/CLAUDE.md"
    printf '[![Version: 1.1.0](https://img.shields.io/badge/Version-1.1.0-green.svg)](VERSION)\n' > "$BATS_TEST_TMPDIR/r/README.md"
    printf '# Evolution Log\n\nv1.1.0 landed.\n' > "$BATS_TEST_TMPDIR/r/docs/evolution-log.md"
    run "$SCRIPT" "$BATS_TEST_TMPDIR/r"
    [ "$status" -eq 0 ]
}

@test "T10: no arguments → exit 2" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
}
