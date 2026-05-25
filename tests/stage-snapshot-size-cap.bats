#!/usr/bin/env bats
#
# TUNE-0254 — body ≤ 8192 → no marker; > 8192 → marker + file ≤ 8192.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
WRITER_LIB="${REPO_ROOT}/scripts/lib/snapshot-writer.sh"

setup() {
    export TMPROOT="$BATS_TEST_TMPDIR/fake-repo"
    mkdir -p "$TMPROOT/datarim"
    export OPTIONS="$BATS_TEST_TMPDIR/options.txt"
    printf '/dr-do TUNE-0254 | go\n' > "$OPTIONS"
    # shellcheck source=/dev/null
    . "$WRITER_LIB"
}

@test "body under 8192 bytes → no truncation marker" {
    local body="$BATS_TEST_TMPDIR/small.txt"
    printf 'short body\n' > "$body"
    write_stage_snapshot \
        --root "$TMPROOT" --task TUNE-0254 --stage plan --command /dr-plan \
        --captured-by agent --recommended-next /dr-do \
        --options-file "$OPTIONS" --body-file "$body"
    local snap="$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md"
    ! grep -q 'snapshot-truncated' "$snap"
    grep -q '^truncated: false$' "$snap"
}

@test "body over 8192 bytes → marker present + file ≤ 8192 + truncated: true" {
    local body="$BATS_TEST_TMPDIR/big.txt"
    python3 -c 'print("Y" * 30000)' > "$body"
    write_stage_snapshot \
        --root "$TMPROOT" --task TUNE-0254 --stage plan --command /dr-plan \
        --captured-by agent --recommended-next /dr-do \
        --options-file "$OPTIONS" --body-file "$body"
    local snap="$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md"
    local size
    size="$(wc -c < "$snap" | tr -d ' ')"
    [ "$size" -le 8192 ]
    grep -q 'snapshot-truncated' "$snap"
    grep -q '^truncated: true$' "$snap"
}
