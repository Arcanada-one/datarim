#!/usr/bin/env bats
#
# Private-overlay contract for personal-id-gate.
#
# The shipped denylist file lives in a PUBLIC repo. Listing literal
# infrastructure addresses in it publishes exactly what the gate exists to
# suppress: the file becomes its own leak. Public-routable IPs need no listing
# (the is_real_public_ipv4 heuristic catches any of them), but CGNAT mesh
# addresses (100.64/10) are deliberately excluded from that heuristic, so they
# can only be caught by an explicit pattern.
#
# Resolution: the shipped file carries NO literal addresses; operator-specific
# values live in a gitignored local overlay that the gate merges when present.
#
# Tests assert BEHAVIOUR (gate exit code), never the presence of prose.

setup() {
    GATE="${BATS_TEST_DIRNAME}/../scripts/personal-id-gate.sh"
    REGEX="${BATS_TEST_DIRNAME}/../dev-tools/personal-id-forbidden.regex"
    [ -x "$GATE" ] || skip "gate not executable"
    TMP_DIR="$(mktemp -d)"
    # Isolate from any REAL operator overlay on the developer's machine: an
    # overlay that happens to list a test address would make an assertion pass
    # for the wrong reason. Every test starts from "no overlay".
    mkdir -p "$TMP_DIR/empty-local"
    export DATARIM_LOCAL="$TMP_DIR/empty-local"
    unset DATARIM_PERSONAL_ID_OVERLAY
}

teardown() {
    rm -rf "$TMP_DIR"
}

# --- P-1: the shipped denylist must not itself carry literal addresses -------
@test "P-1 shipped regex file contains no literal IPv4 address patterns" {
    run grep -cE '^\\b[0-9]{1,3}\\\.[0-9]{1,3}\\\.[0-9]{1,3}\\\.[0-9]{1,3}\\b$' "$REGEX"
    # grep -c prints 0 and exits 1 when there are no matches
    [ "$output" -eq 0 ]
}

# --- P-2: public-routable IP still caught (heuristic, no listing needed) -----
@test "P-2 real public IPv4 still flagged without any denylist entry" {
    printf 'deploy target 203.0.113.9 is documentation-range\n' > "$TMP_DIR/doc.txt"
    printf 'deploy target 65.108.236.39 is a real host\n' > "$TMP_DIR/real.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/real.txt" --check
    [ "$status" -eq 1 ]
}

# --- P-3: RFC 5737 documentation range must NOT be flagged ------------------
@test "P-3 RFC 5737 documentation address is not flagged" {
    printf 'example host 203.0.113.9 for docs\n' > "$TMP_DIR/doc.txt"
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/doc.txt" --check
    [ "$status" -eq 0 ]
}

# --- P-4: CGNAT mesh address caught via the local overlay -------------------
@test "P-4 CGNAT mesh address flagged when a local overlay supplies it" {
    printf 'mesh peer 100.78.174.28 reachable\n' > "$TMP_DIR/mesh.txt"

    # Without an overlay the heuristic deliberately skips 100.64/10.
    run bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/mesh.txt" --check
    [ "$status" -eq 0 ]

    # With the overlay the same content must be flagged.
    printf '\\b100\\.78\\.174\\.28\\b\n' > "$TMP_DIR/local.regex"
    run env DATARIM_PERSONAL_ID_OVERLAY="$TMP_DIR/local.regex" \
        bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/mesh.txt" --check
    [ "$status" -eq 1 ]
}

# --- P-5: a missing overlay must not break the gate (fail-soft) -------------
@test "P-5 absent overlay path is ignored, gate still functions" {
    printf 'clean content with no identifiers\n' > "$TMP_DIR/clean.txt"
    run env DATARIM_PERSONAL_ID_OVERLAY="$TMP_DIR/does-not-exist.regex" \
        bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/clean.txt" --check
    [ "$status" -eq 0 ]
}

# --- P-6: overlay must not silence the shipped patterns ---------------------
@test "P-6 overlay is additive — shipped patterns still enforced" {
    printf 'contact pavel about this\n' > "$TMP_DIR/name.txt"
    printf '\\bunrelated-token\\b\n' > "$TMP_DIR/local.regex"
    run env DATARIM_PERSONAL_ID_OVERLAY="$TMP_DIR/local.regex" \
        bash "$GATE" --regex "$REGEX" --paths "$TMP_DIR/name.txt" --check
    [ "$status" -eq 1 ]
}
