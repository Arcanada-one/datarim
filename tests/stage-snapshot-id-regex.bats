#!/usr/bin/env bats
#
# Regression tests for the TASK-ID regex in snapshot-writer.sh.
#
# Verifies:
#   - Slug-suffix IDs (e.g. DEV-1438-FU-engage-generator-perf) are accepted.
#   - Canonical short IDs (e.g. TUNE-0334) continue to be accepted.
#   - Path-traversal and malformed IDs are still rejected (T-1 security control).
#
# Canonical regex: ^[A-Z]{2,10}-[0-9]{4}(-[A-Za-z0-9]+)*$

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
WRITER_LIB="${REPO_ROOT}/scripts/lib/snapshot-writer.sh"

setup() {
    export TMPROOT="$BATS_TEST_TMPDIR/fake-repo"
    mkdir -p "$TMPROOT/datarim"
    export OPTIONS="$BATS_TEST_TMPDIR/options.txt"
    printf '/dr-qa TUNE-0334 | verify\n' > "$OPTIONS"
    export BODY="$BATS_TEST_TMPDIR/body.txt"
    printf 'snapshot body for regex regression test\n' > "$BODY"
    # shellcheck source=/dev/null
    . "$WRITER_LIB"
}

# ---------------------------------------------------------------------------
# Accepted IDs
# ---------------------------------------------------------------------------

@test "canonical 4-digit ID (TUNE-0334) is accepted" {
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task TUNE-0334 \
        --stage 'do' \
        --command /dr-do \
        --captured-by agent \
        --recommended-next /dr-qa \
        --options-file "$OPTIONS" \
        --body-file "$BODY"
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/datarim/snapshots/TUNE-0334.snapshot.md" ]
}

@test "slug-suffix FU ID (DEV-1438-FU-engage-generator-perf) is accepted" {
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task DEV-1438-FU-engage-generator-perf \
        --stage 'do' \
        --command /dr-do \
        --captured-by agent \
        --recommended-next /dr-qa \
        --options-file "$OPTIONS" \
        --body-file "$BODY"
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/datarim/snapshots/DEV-1438-FU-engage-generator-perf.snapshot.md" ]
}

@test "multi-segment suffix ID (INFRA-0042-hotfix-db) is accepted" {
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task INFRA-0042-hotfix-db \
        --stage plan \
        --command /dr-plan \
        --captured-by agent \
        --recommended-next /dr-do \
        --options-file "$OPTIONS" \
        --body-file "$BODY"
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/datarim/snapshots/INFRA-0042-hotfix-db.snapshot.md" ]
}

@test "10-char prefix ID (ABCDEFGHIJ-0001) is accepted (max prefix length)" {
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task ABCDEFGHIJ-0001 \
        --stage 'do' \
        --command /dr-do \
        --captured-by agent \
        --recommended-next /dr-qa \
        --options-file "$OPTIONS" \
        --body-file "$BODY"
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/datarim/snapshots/ABCDEFGHIJ-0001.snapshot.md" ]
}

# ---------------------------------------------------------------------------
# Rejected IDs — T-1 path-traversal + malformed (security control)
# ---------------------------------------------------------------------------

@test "path-traversal ../etc/passwd is rejected (T-1)" {
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task '../etc/passwd' \
        --stage 'do' \
        --command /dr-do \
        --captured-by agent \
        --recommended-next /dr-qa \
        --options-file "$OPTIONS" \
        --body-file "$BODY"
    [ "$status" -eq 1 ]
    [ ! -f "$TMPROOT/datarim/snapshots/../etc/passwd.snapshot.md" ]
}

@test "ID with slash (FOO/../bar) is rejected (T-1)" {
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task 'FOO/../bar' \
        --stage 'do' \
        --command /dr-do \
        --captured-by agent \
        --recommended-next /dr-qa \
        --options-file "$OPTIONS" \
        --body-file "$BODY"
    [ "$status" -eq 1 ]
}

@test "too-short prefix (AB-1234) is rejected — prefix requires 2+ uppercase chars (already 2; only 1-char prefix rejected)" {
    # AB has 2 chars which satisfies {2,10} — so AB-1234 MUST be accepted.
    # This test documents that 1-char prefix single-letter IDs like A-1234 are rejected.
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task 'A-1234' \
        --stage 'do' \
        --command /dr-do \
        --captured-by agent \
        --recommended-next /dr-qa \
        --options-file "$OPTIONS" \
        --body-file "$BODY"
    [ "$status" -eq 1 ]
}

@test "lowercase prefix (lowercase-0001) is rejected" {
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task 'lowercase-0001' \
        --stage 'do' \
        --command /dr-do \
        --captured-by agent \
        --recommended-next /dr-qa \
        --options-file "$OPTIONS" \
        --body-file "$BODY"
    [ "$status" -eq 1 ]
}

@test "3-digit number (TUNE-034) is rejected — requires 4 digits" {
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task 'TUNE-034' \
        --stage 'do' \
        --command /dr-do \
        --captured-by agent \
        --recommended-next /dr-qa \
        --options-file "$OPTIONS" \
        --body-file "$BODY"
    [ "$status" -eq 1 ]
}

@test "ID with dot (TUNE-0334.bak) is rejected — dots not in suffix charclass" {
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task 'TUNE-0334.bak' \
        --stage 'do' \
        --command /dr-do \
        --captured-by agent \
        --recommended-next /dr-qa \
        --options-file "$OPTIONS" \
        --body-file "$BODY"
    [ "$status" -eq 1 ]
}

@test "ID with space (TUNE 0334) is rejected" {
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task 'TUNE 0334' \
        --stage 'do' \
        --command /dr-do \
        --captured-by agent \
        --recommended-next /dr-qa \
        --options-file "$OPTIONS" \
        --body-file "$BODY"
    [ "$status" -eq 1 ]
}

@test "prefix longer than 10 chars (ABCDEFGHIJK-0001) is rejected" {
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task 'ABCDEFGHIJK-0001' \
        --stage 'do' \
        --command /dr-do \
        --captured-by agent \
        --recommended-next /dr-qa \
        --options-file "$OPTIONS" \
        --body-file "$BODY"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Snapshot content sanity for slug-suffix IDs
# ---------------------------------------------------------------------------

@test "snapshot written for slug-suffix ID has correct task_id in frontmatter" {
    write_stage_snapshot \
        --root "$TMPROOT" \
        --task DEV-1438-FU-engage-generator-perf \
        --stage 'do' \
        --command /dr-do \
        --captured-by agent \
        --recommended-next /dr-qa \
        --options-file "$OPTIONS" \
        --body-file "$BODY"
    local snap="$TMPROOT/datarim/snapshots/DEV-1438-FU-engage-generator-perf.snapshot.md"
    grep -q '^task_id: DEV-1438-FU-engage-generator-perf$' "$snap"
    grep -q '^artifact: stage-snapshot$' "$snap"
}
