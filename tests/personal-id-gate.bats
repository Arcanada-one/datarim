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

# --- Real-public-IPv4 heuristic (forward leak prevention) ------------------

@test "heuristic: fresh unlisted real public IP (188.34.155.2) → exit 1" {
    printf 'ssh dev@188.34.155.2 to reach the new box\n' > "$TMP_DIR/newip.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/newip.txt" --check
    [ "$status" -eq 1 ]
}

@test "heuristic: another fresh unlisted real public IP (5.161.70.100) → exit 1" {
    printf 'DB_HOST=5.161.70.100\n' > "$TMP_DIR/newip2.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/newip2.txt" --check
    [ "$status" -eq 1 ]
}

@test "heuristic: RFC 5737 TEST-NET-3 (203.0.113.10) → exit 0 (not flagged)" {
    printf 'example host 203.0.113.10 for docs\n' > "$TMP_DIR/testnet3.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/testnet3.txt" --check
    [ "$status" -eq 0 ]
}

@test "heuristic: RFC 5737 TEST-NET-1 (192.0.2.5) → exit 0 (not flagged)" {
    printf 'placeholder 192.0.2.5 in a tutorial\n' > "$TMP_DIR/testnet1.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/testnet1.txt" --check
    [ "$status" -eq 0 ]
}

@test "heuristic: RFC 5737 TEST-NET-2 (198.51.100.7) → exit 0 (not flagged)" {
    printf 'sample 198.51.100.7 documentation\n' > "$TMP_DIR/testnet2.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/testnet2.txt" --check
    [ "$status" -eq 0 ]
}

@test "heuristic: RFC 1918 private ranges (10/172.16/192.168) → exit 0" {
    printf 'bind 10.0.0.12\nlisten 192.168.1.1\nmesh 172.16.5.5\n' > "$TMP_DIR/private.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/private.txt" --check
    [ "$status" -eq 0 ]
}

@test "heuristic: loopback (127.0.0.1) → exit 0 (not flagged)" {
    printf 'server binds 127.0.0.1 loopback only\n' > "$TMP_DIR/loopback.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/loopback.txt" --check
    [ "$status" -eq 0 ]
}

@test "heuristic: version string 2.53.0 → exit 0 (3-part, not a quad)" {
    printf 'VERSION 2.53.0 released today\n' > "$TMP_DIR/version3.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/version3.txt" --check
    [ "$status" -eq 0 ]
}

@test "heuristic: 4-part version-like 1.0.0.0 → exit 0 (4th octet 0)" {
    printf 'schema version 1.0.0.0 baseline\n' > "$TMP_DIR/version4.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/version4.txt" --check
    [ "$status" -eq 0 ]
}

@test "heuristic: dotted section number 0.2.5.1 → exit 0 (0.0.0.0/8)" {
    printf '0.2.5.1 Local == origin. Confirm the commit.\n' > "$TMP_DIR/secnum.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/secnum.txt" --check
    [ "$status" -eq 0 ]
}

@test "heuristic: CGNAT/Tailscale example 100.64.1.5 → exit 0 (100.64/10)" {
    printf 'Tier 2 example bind 100.64.1.5:5432\n' > "$TMP_DIR/cgnat.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/cgnat.txt" --check
    [ "$status" -eq 0 ]
}

@test "heuristic: real public IP inside example-fence → exit 0 (fence wins)" {
    printf '<!-- gate:example-only -->\nssh root@188.34.155.2 counter-example\n<!-- /gate:example-only -->\n' \
        > "$TMP_DIR/fenced-ip.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/fenced-ip.txt" --check
    [ "$status" -eq 0 ]
}

@test "heuristic: real public IP outside fence still flagged after a closed fence → exit 1" {
    cat > "$TMP_DIR/mixed-ip.txt" << 'FIXTURE'
<!-- gate:example-only -->
198.51.100.7 is a safe documentation address
<!-- /gate:example-only -->
But 65.108.236.39 out here is a real host and must be caught.
FIXTURE
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/mixed-ip.txt" --check
    [ "$status" -eq 1 ]
}
