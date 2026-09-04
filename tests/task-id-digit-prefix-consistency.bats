#!/usr/bin/env bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
LEGACY_REGEX='[A-Z]''{2,10}'

@test "active shipped surfaces no longer use the letters-only task-prefix regex" {
    run grep -R -F -n \
        --exclude-dir=.git \
        --exclude='PRD-TUNE-0574.md' \
        --exclude='evolution-log.md' \
        -- "$LEGACY_REGEX" "$REPO_ROOT"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "frozen historical records retain their original regex evidence" {
    grep -F -- "$LEGACY_REGEX" "$REPO_ROOT/datarim/prd/PRD-TUNE-0574.md"
    grep -F -- "$LEGACY_REGEX" "$REPO_ROOT/documentation/how-to/evolution-log.md"
}
