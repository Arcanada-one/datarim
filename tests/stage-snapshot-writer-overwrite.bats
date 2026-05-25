#!/usr/bin/env bats
#
# TUNE-0254 — stage-snapshot writer: overwrite + truncation + invalid input.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
WRITER_LIB="${REPO_ROOT}/scripts/lib/snapshot-writer.sh"

setup() {
    export TMPROOT="$BATS_TEST_TMPDIR/fake-repo"
    mkdir -p "$TMPROOT/datarim"
    export OPTIONS="$BATS_TEST_TMPDIR/options.txt"
    cat > "$OPTIONS" <<'OPT'
/dr-do TUNE-0254 | реализация плана
/dr-status | escape hatch
OPT
    export BODY1="$BATS_TEST_TMPDIR/body1.txt"
    export BODY2="$BATS_TEST_TMPDIR/body2.txt"
    printf 'first stage body — round 1\nLine 2 of round 1\n' > "$BODY1"
    printf 'completely different body — round 2 replaces round 1\n' > "$BODY2"
    # shellcheck source=/dev/null
    . "$WRITER_LIB"
}

@test "first write creates snapshot file with canonical frontmatter shape" {
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task TUNE-0254 \
        --stage plan \
        --command /dr-plan \
        --captured-by agent \
        --recommended-next /dr-do \
        --options-file "$OPTIONS" \
        --body-file "$BODY1"
    [ "$status" -eq 0 ]
    local snap="$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md"
    [ -f "$snap" ]
    grep -q '^task_id: TUNE-0254$' "$snap"
    grep -q '^artifact: stage-snapshot$' "$snap"
    grep -q '^schema_version: 1$' "$snap"
    grep -q '^stage: plan$' "$snap"
    grep -q '^command: /dr-plan$' "$snap"
    grep -q '^captured_by: agent$' "$snap"
    grep -q '^recommended_next: /dr-do$' "$snap"
    grep -q '^truncated: false$' "$snap"
    grep -q 'first stage body — round 1' "$snap"
}

@test "second write fully overwrites the first (no residue, line count matches body2)" {
    write_stage_snapshot \
        --root "$TMPROOT" --task TUNE-0254 --stage plan --command /dr-plan \
        --captured-by agent --recommended-next /dr-do \
        --options-file "$OPTIONS" --body-file "$BODY1"
    write_stage_snapshot \
        --root "$TMPROOT" --task TUNE-0254 --stage do --command /dr-do \
        --captured-by agent --recommended-next /dr-qa \
        --options-file "$OPTIONS" --body-file "$BODY2"
    local snap="$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md"
    grep -q 'completely different body — round 2' "$snap"
    ! grep -q 'first stage body — round 1' "$snap"
    grep -q '^stage: do$' "$snap"
    grep -q '^command: /dr-do$' "$snap"
}

@test "body over 8192 bytes truncated with marker; file ≤ 8192 bytes" {
    local big="$BATS_TEST_TMPDIR/big.txt"
    # 20 KB body — well over cap.
    python3 -c 'print("X" * 20000)' > "$big"
    run write_stage_snapshot \
        --root "$TMPROOT" --task TUNE-0254 --stage plan --command /dr-plan \
        --captured-by agent --recommended-next /dr-do \
        --options-file "$OPTIONS" --body-file "$big"
    [ "$status" -eq 0 ]
    local snap="$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md"
    local size
    size="$(wc -c < "$snap" | tr -d ' ')"
    [ "$size" -le 8192 ]
    grep -q 'snapshot-truncated' "$snap"
    grep -q '^truncated: true$' "$snap"
}

@test "invalid TASK-ID rejected with exit 1, no file created" {
    run write_stage_snapshot \
        --root "$TMPROOT" --task '../etc/passwd' --stage plan --command /dr-plan \
        --captured-by agent --recommended-next /dr-do \
        --options-file "$OPTIONS" --body-file "$BODY1"
    [ "$status" -eq 1 ]
    [ ! -f "$TMPROOT/datarim/snapshots/../etc/passwd.snapshot.md" ]
}

@test "missing required arg → exit 2 (usage)" {
    run write_stage_snapshot --root "$TMPROOT" --task TUNE-0254 --stage plan
    [ "$status" -eq 2 ]
}

@test "DATARIM_DISABLE_SNAPSHOT=1 makes writer no-op (exit 0, no file)" {
    DATARIM_DISABLE_SNAPSHOT=1 run write_stage_snapshot \
        --root "$TMPROOT" --task TUNE-0254 --stage plan --command /dr-plan \
        --captured-by agent --recommended-next /dr-do \
        --options-file "$OPTIONS" --body-file "$BODY1"
    [ "$status" -eq 0 ]
    [ ! -f "$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md" ]
}

@test "snapshot file is chmod 600 (least-privilege Appendix A control)" {
    write_stage_snapshot \
        --root "$TMPROOT" --task TUNE-0254 --stage plan --command /dr-plan \
        --captured-by agent --recommended-next /dr-do \
        --options-file "$OPTIONS" --body-file "$BODY1"
    local snap="$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md"
    local mode
    if mode="$(stat -f '%Lp' "$snap" 2>/dev/null)"; then :; else
        mode="$(stat -c '%a' "$snap")"
    fi
    [ "$mode" = "600" ]
}
