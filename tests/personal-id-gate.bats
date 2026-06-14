#!/usr/bin/env bats
# personal-id-gate.bats — contract tests for scripts/personal-id-gate.sh.
# Six contracts from the plan.

setup() {
    GATE="${BATS_TEST_DIRNAME}/../scripts/personal-id-gate.sh"
    REGEX="${BATS_TEST_DIRNAME}/../dev-tools/personal-id-forbidden.regex"
    TMP_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "synthetic fixture with forbidden token (paxbeach) → exit 1" {
    printf 'hello paxbeach world\n' > "$TMP_DIR/test-fixture.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/test-fixture.txt" --check
    [ "$status" -eq 1 ]
}

@test "synthetic fixture with 16-digit GID → exit 1" {
    printf 'workspace_gid=1234567890123456\n' > "$TMP_DIR/test-fixture.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/test-fixture.txt" --check
    [ "$status" -eq 1 ]
}

@test "clean content → exit 0" {
    printf 'This is generic framework documentation.\n' > "$TMP_DIR/clean.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/clean.txt" --check
    [ "$status" -eq 0 ]
}

@test "whitelisted path → exit 0 even with forbidden token" {
    mkdir -p "$TMP_DIR/whitelisted"
    printf 'paxbeach is mentioned here\n' > "$TMP_DIR/whitelisted/doc.txt"
    printf '%s\n' "$TMP_DIR/whitelisted" > "$TMP_DIR/whitelist.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/whitelisted/doc.txt" \
        --whitelist "$TMP_DIR/whitelist.txt" --check
    [ "$status" -eq 0 ]
}

@test "gate:example-only fenced line with forbidden token → exit 0" {
    # Content inside <!-- gate:example-only --> ... <!-- /gate:example-only -->
    # must be excluded from scanning.
    printf '<!-- gate:example-only -->\nPavel Valentov paxbeach example\n<!-- /gate:example-only -->\n' \
        > "$TMP_DIR/fenced.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/fenced.txt" --check
    [ "$status" -eq 0 ]
}

@test "em-dash in ordinary text → exit 0 (no false positive)" {
    printf 'user@host \xe2\x80\x94 description of feature\n' > "$TMP_DIR/emdash.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/emdash.txt" --check
    [ "$status" -eq 0 ]
}

@test "prose mention of gate:example-only marker with forbidden token → exit 1 (regression: fence-masking bug)" {
    # A line that MENTIONS the marker substring inside backticks or prose must NOT
    # open the fence. Only a whole-line <!-- gate:example-only --> should do so.
    # This test guards the fix for the fence-masking bug where a narrative mention
    # would set $in_fence=1 with no matching closing line, silently skipping EOF.
    cat > "$TMP_DIR/prose-mention.txt" << 'FIXTURE'
This document explains how `<!-- gate:example-only -->` markers work in the framework.
Pavel Valentov paxbeach is a personal identifier that should be caught.
FIXTURE
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/prose-mention.txt" --check
    [ "$status" -eq 1 ]
}

@test "whole-line gate:example-only fence still excludes content → exit 0" {
    # A proper whole-line fence should still work after the anchoring fix.
    cat > "$TMP_DIR/proper-fence.txt" << 'FIXTURE'
Text before fence.
<!-- gate:example-only -->
Pavel Valentov paxbeach inside proper whole-line fence
<!-- /gate:example-only -->
Text after fence.
FIXTURE
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/proper-fence.txt" --check
    [ "$status" -eq 0 ]
}
