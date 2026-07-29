#!/usr/bin/env bats
#
# TUNE-0517: STAGING-NOT-STALE wiring test.
# Verifies the STAGING-NOT-STALE pre-check rule in dr-do.md references an
# executable check script that agents can invoke for staging-liveness
# verification. Prior to this test, the rule was prose-only (UNENFORCED).
# Wiring adds a load-path and a check script, upgrading to ENFORCED-LOAD.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DR_DO_DOC="$REPO_ROOT/commands/dr-do.md"
CHECK_SCRIPT="$REPO_ROOT/dev-tools/check-staging-not-stale.sh"

@test "STAGING-NOT-STALE: dr-do.md references check-staging-not-stale.sh" {
    [ -f "$DR_DO_DOC" ]
    run grep -F "check-staging-not-stale" "$DR_DO_DOC"
    [ "$status" -eq 0 ]
}

@test "STAGING-NOT-STALE: check-staging-not-stale.sh exists and is executable" {
    [ -f "$CHECK_SCRIPT" ]
    [ -x "$CHECK_SCRIPT" ]
}

@test "STAGING-NOT-STALE: check-staging-not-stale.sh --help exits 0 and shows usage" {
    run "$CHECK_SCRIPT" --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "usage\|staging\|stale\|check"
}

@test "STAGING-NOT-STALE: check-staging-not-stale.sh without args exits 2" {
    run "$CHECK_SCRIPT"
    [ "$status" -eq 2 ]
}
