#!/usr/bin/env bats
#
# Regression for the /dr-plan Step 6.5 "External target reality-probe" bullet.
#
# The probe is a prose gate embedded in commands/dr-plan.md (there is no
# standalone probe script), so the regression locks the documented gate
# contract: a future edit cannot silently drop or weaken any of the three
# behaviours the bullet promises. Covers the three cases the gate specifies:
#   (a) `ls "<path>"` existence check on a cited filesystem target,
#   (b) HTTP 200 check on a cited web target,
#   (c) HTTP 000 / DNS-does-not-resolve => stale => pause + ask the operator.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    PLAN="$REPO_ROOT/commands/dr-plan.md"
}

@test "dr-plan: External target reality-probe bullet is present" {
    grep -qF 'External target reality-probe' "$PLAN"
}

@test "dr-plan reality-probe (a): documents the ls existence check" {
    # `ls "<path>"` MUST return a real entry — the filesystem-target arm
    grep -qF 'ls "<path>"' "$PLAN"
    grep -qF 'MUST return a real entry' "$PLAN"
}

@test "dr-plan reality-probe (b): documents the HTTP 200 web-target check" {
    # curl ... -w '%{http_code}' MUST return 200 for a live web target
    grep -qF '%{http_code}' "$PLAN"
    grep -qE 'MUST return `?200' "$PLAN"
}

@test "dr-plan reality-probe (c): HTTP 000 / DNS-not-found => operator block" {
    # non-resolving target (HTTP 000) is the stale-memory signal that blocks
    grep -qF 'HTTP `000`' "$PLAN"
    grep -qF 'DNS does not resolve' "$PLAN"
    grep -qF 'pause and ask the operator' "$PLAN"
}
