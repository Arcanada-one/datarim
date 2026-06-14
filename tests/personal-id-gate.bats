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
