#!/usr/bin/env bats
#
# Reintroduction guard: no real infrastructure address may appear anywhere in
# this repository — not in the shipped surface, and not in a test fixture.
#
# Two defects motivate this test, and neither was caught by the gate:
#
#   1. A denylist that enumerates the values it forbids is its own leak. The
#      shipped denylist was emptied of literal addresses for that reason, and
#      the operator's values moved to a gitignored overlay.
#   2. Emptying the denylist does not help if the same literals survive in the
#      TEST that proves the denylist is empty. A fixture is not a safe place to
#      put a real value: a public repo publishes its tests too.
#
# The gate itself cannot close (2): its scan scope is the shipped surface, and
# tests/ is deliberately outside it. Hence a separate check.
#
# Mechanism, and why it carries no forbidden value of its own: the value set is
# read at runtime from the same gitignored overlay the gate merges. This file
# names no address. With no overlay present (fresh clone, CI) there is nothing
# to compare against and the test skips — it is a developer-machine guard, not
# a CI gate, exactly like the overlay it depends on.
#
# Matching is escape-insensitive. A literal reaches a regex, sed expression, or
# denylist entry as `1\.2\.3\.4` or `1\\.2\\.3\\.4`, and a plain search for the
# dotted quad silently misses both — the same blind spot hides such a value from
# `git log -S'1.2.3.4'`. Each needle therefore becomes an ERE in which every dot
# is preceded by `\\*` (zero or more literal backslashes), which collapses all
# escape depths into one pattern.

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

    OVERLAY=""
    if [ -n "${DATARIM_PERSONAL_ID_OVERLAY:-}" ] && [ -f "${DATARIM_PERSONAL_ID_OVERLAY}" ]; then
        OVERLAY="${DATARIM_PERSONAL_ID_OVERLAY}"
    elif [ -f "${DATARIM_LOCAL:-$HOME/.claude/local}/config/personal-id-forbidden.regex" ]; then
        OVERLAY="${DATARIM_LOCAL:-$HOME/.claude/local}/config/personal-id-forbidden.regex"
    fi

    TMP_DIR="$(mktemp -d)"
    PATTERNS="$TMP_DIR/patterns.txt"
}

teardown() {
    rm -rf "$TMP_DIR"
}

# This file contains detector mechanics but no real address. All dead-IP sweep
# fixtures use RFC 5737 documentation space and are scanned like shipped code.
EXEMPT_PATHS=':!tests/personal-id-no-real-values.bats'

@test "no real infrastructure address appears anywhere in the repository" {
    [ -n "$OVERLAY" ] || skip "no local overlay present — nothing to compare against"

    # Reduce overlay patterns to bare dotted quads, then re-emit each as an
    # escape-tolerant ERE.
    #
    # No \b in the extraction: stripping backslashes turns the anchored form
    # `\b1.2.3.4\b` into `b1.2.3.4b`, where a leading word boundary can never
    # match. That mistake yields an empty pattern set and a test that skips
    # instead of checking — a silent false green.
    tr -d '\\' < "$OVERLAY" \
        | sed 's/^[[:space:]]*//' \
        | grep -v '^#' \
        | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' \
        | sort -u \
        | sed 's/\./\\\\*\\./g' > "$PATTERNS"

    [ -s "$PATTERNS" ] || skip "overlay declares no literal IPv4 to check"

    cd "$REPO_ROOT"
    # git grep confines the scan to tracked files, so an untracked scratch file
    # cannot fail the build. Report LOCATIONS only — echoing a matched value
    # would make a failing CI log the same leak this test exists to prevent.
    run git grep -I -n -E -f "$PATTERNS" -- . $EXEMPT_PATHS
    findings="$(printf '%s' "$output" | grep -c . || true)"

    if [ "$status" -eq 0 ]; then
        echo "$findings real-address reference(s) found (values redacted):"
        printf '%s\n' "$output" | cut -d: -f1,2 | sed 's/$/: real infrastructure address/'
        echo
        echo "Fix: replace the fixture with a synthetic equivalent."
        echo "  routable-but-nobody's  -> 198.18.0.0/15 (RFC 2544 benchmarking)"
        echo "  documentation          -> 192.0.2/24, 198.51.100/24, 203.0.113/24"
        echo "  CGNAT / mesh           -> any unassigned address in 100.64/10"
        echo "Add an exemption only when the address IS the detector's needle."
    fi
    # git grep exits 1 when nothing matched — that is the clean outcome.
    [ "$status" -eq 1 ]
}
