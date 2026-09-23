#!/usr/bin/env bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
LEGACY_REGEX='[A-Z]''{2,10}'

@test "active shipped surfaces no longer use the letters-only task-prefix regex" {
    # Frozen historical evidence is excluded by name, never by a broad directory
    # skip: a shipped surface must not be able to hide behind the fixtures tree.
    run grep -R -F -n \
        --exclude-dir=.git \
        --exclude='PRD-TUNE-0574-regex-evidence.md' \
        --exclude='evolution-log.md' \
        -- "$LEGACY_REGEX" "$REPO_ROOT"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "frozen historical records retain their original regex evidence" {
    # The product root no longer ships a datarim/ knowledge base, so the PRD's
    # frozen excerpt lives with the other legacy expectations. The assertion is
    # unchanged: historical records must still carry the old letters-only form.
    grep -F -- "$LEGACY_REGEX" \
        "$REPO_ROOT/tests/fixtures/legacy-expectations/datarim/prd/PRD-TUNE-0574-regex-evidence.md"
    grep -F -- "$LEGACY_REGEX" "$REPO_ROOT/documentation/how-to/evolution-log.md"
}
