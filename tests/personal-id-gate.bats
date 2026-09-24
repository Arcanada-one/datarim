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

@test "synthetic fixture with forbidden token (operator) → exit 1" {
    printf 'hello operator world\n' > "$TMP_DIR/test-fixture.txt"
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
    printf 'operator is mentioned here\n' > "$TMP_DIR/whitelisted/doc.txt"
    printf '%s\n' "$TMP_DIR/whitelisted" > "$TMP_DIR/whitelist.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/whitelisted/doc.txt" \
        --whitelist "$TMP_DIR/whitelist.txt" --check
    [ "$status" -eq 0 ]
}

@test "gate:example-only fenced line with forbidden token → exit 0" {
    # Content inside <!-- gate:example-only --> ... <!-- /gate:example-only -->
    # must be excluded from scanning.
    printf '<!-- gate:example-only -->\nArcanada operator example\n<!-- /gate:example-only -->\n' \
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
Arcanada operator is a personal identifier that should be caught.
FIXTURE
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/prose-mention.txt" --check
    [ "$status" -eq 1 ]
}

@test "whole-line gate:example-only fence still excludes content → exit 0" {
    # A proper whole-line fence should still work after the anchoring fix.
    cat > "$TMP_DIR/proper-fence.txt" << 'FIXTURE'
Text before fence.
<!-- gate:example-only -->
Arcanada operator inside proper whole-line fence
<!-- /gate:example-only -->
Text after fence.
FIXTURE
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/proper-fence.txt" --check
    [ "$status" -eq 0 ]
}

# --- Real-public-IPv4 heuristic (forward leak prevention) ------------------

@test "heuristic: fresh unlisted real public IP (9.9.9.9) → exit 1" {
    printf 'ssh dev@9.9.9.9 to reach the new box\n' > "$TMP_DIR/newip.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/newip.txt" --check
    [ "$status" -eq 1 ]
}

@test "heuristic: another fresh unlisted real public IP (1.1.1.1) → exit 1" {
    printf 'DB_HOST=1.1.1.1\n' > "$TMP_DIR/newip2.txt"
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
    printf '<!-- gate:example-only -->\nssh root@9.9.9.9 counter-example\n<!-- /gate:example-only -->\n' \
        > "$TMP_DIR/fenced-ip.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/fenced-ip.txt" --check
    [ "$status" -eq 0 ]
}

@test "heuristic: real public IP outside fence still flagged after a closed fence → exit 1" {
    cat > "$TMP_DIR/mixed-ip.txt" << 'FIXTURE'
<!-- gate:example-only -->
198.51.100.7 is a safe documentation address
<!-- /gate:example-only -->
But 8.8.8.8 out here is a routable public address and must be caught.
FIXTURE
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/mixed-ip.txt" --check
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Consumer-coupling classes. Each pair is a planted identifier that must go red
# and a near miss that must stay green, so a pattern that matches nothing (or
# everything) fails here rather than reporting a clean tree.
# ---------------------------------------------------------------------------

@test "consumer task id DEV-1926 cited as provenance → exit 1" {
    printf 'ported from DEV-1926 in the client repo\n' > "$TMP_DIR/f.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/f.txt" --check
    [ "$status" -eq 1 ]
}

@test "synthetic fixture ids DEV-0226 / DEV-9876 → exit 0" {
    printf -- '- **DEV-0226** — fixture\n- **DEV-9876** — fixture\n' > "$TMP_DIR/f.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/f.txt" --check
    [ "$status" -eq 0 ]
}

@test "vendor-specific tracker field asanaGid / asana_gid → exit 1" {
    printf "fields: ['taskId', 'asanaGid']\n" > "$TMP_DIR/a.txt"
    printf 'asana_gid: 42\n' > "$TMP_DIR/b.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/a.txt" --check
    [ "$status" -eq 1 ]
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/b.txt" --check
    [ "$status" -eq 1 ]
}

@test "generic tracker field trackerRef → exit 0" {
    printf "fields: ['taskId', 'trackerRef']\n" > "$TMP_DIR/f.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/f.txt" --check
    [ "$status" -eq 0 ]
}

@test "consumer project name (client) → exit 1" {
    printf 'cd ~/code/client/local-stack\n' > "$TMP_DIR/f.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/f.txt" --check
    [ "$status" -eq 1 ]
}

@test "host family host-devs is caught (word-boundary regression) → exit 1" {
    # The old entry \bhost-dev\b could not match host-devs.
    printf 'measured on host-devs\n' > "$TMP_DIR/f.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/f.txt" --check
    [ "$status" -eq 1 ]
}

@test "absolute macOS home path /Users/<name> → exit 1" {
    printf 'export X="/Users/jdoe/code/proj"\n' > "$TMP_DIR/f.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/f.txt" --check
    [ "$status" -eq 1 ]
}

@test "absolute Linux home path /home/<name> → exit 1" {
    printf 'dd of=/home/jdoe/images/sda\n' > "$TMP_DIR/f.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/f.txt" --check
    [ "$status" -eq 1 ]
}

@test "agent project-state slug -Users-<name>- → exit 1" {
    printf '~/.claude/projects/-Users-jdoe-work/memory/x.md\n' > "$TMP_DIR/f.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/f.txt" --check
    [ "$status" -eq 1 ]
}

@test "home-path placeholders and URL paths stay clean → exit 0" {
    cat > "$TMP_DIR/f.txt" <<'FIXTURE'
/Users/example/code/myproject and /Users/YOUR_USER/.claude and /Users/<user>
/home/example/x /home/app/.claude /home/runner/work /home/<user> $HOME/code
https://hub.docker.com/v2/users/login and rm -rf /Users/../Users
FIXTURE
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/f.txt" --check
    [ "$status" -eq 0 ]
}

@test "tailnet MagicDNS suffix → exit 1" {
    printf '"DNSName": "db.tail0a1b2c.ts.net."\n' > "$TMP_DIR/f.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/f.txt" --check
    [ "$status" -eq 1 ]
}

@test "tracked scope: a planted root-level file is caught; the old path list never saw it" {
    # Build a throwaway repo shaped like the framework (gate + regex at their
    # real relative paths) and plant a leak at the ROOT, outside every
    # DEFAULT_PATHS entry — the shape of the notes file that shipped a home path.
    local repo="$TMP_DIR/repo"
    mkdir -p "$repo/scripts" "$repo/dev-tools"
    cp "$GATE" "$repo/scripts/personal-id-gate.sh"
    cp "$REGEX" "$repo/dev-tools/personal-id-forbidden.regex"
    printf 'checkout at /Users/jdoe/code/x\n' > "$repo/ROOT-NOTES.md"
    git -C "$repo" init -q
    git -C "$repo" add -A
    # Relative DEFAULT_PATHS entries resolve against the CWD first, so run from
    # inside the throwaway repo, not from the framework checkout.
    cd "$repo"
    # Red in tracked scope.
    run env -u DATARIM_PERSONAL_ID_OVERLAY HOME="$TMP_DIR" bash "$repo/scripts/personal-id-gate.sh" --report
    [ "$status" -eq 1 ]
    [[ "$output" == *"ROOT-NOTES.md:1:"* ]]
    # The previous scope (DEFAULT_PATHS) reports PASS on the same tree: the
    # blind spot this test exists to keep closed.
    run env -u DATARIM_PERSONAL_ID_OVERLAY HOME="$TMP_DIR" DATARIM_PERSONAL_ID_SCOPE=paths \
        bash "$repo/scripts/personal-id-gate.sh" --report
    [ "$status" -eq 0 ]
    # Green once the identifier is replaced.
    printf 'checkout at $HOME/code/x\n' > "$repo/ROOT-NOTES.md"
    run env -u DATARIM_PERSONAL_ID_OVERLAY HOME="$TMP_DIR" bash "$repo/scripts/personal-id-gate.sh" --report
    [ "$status" -eq 0 ]
}
