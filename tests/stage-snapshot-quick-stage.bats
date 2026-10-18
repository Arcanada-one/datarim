#!/usr/bin/env bats
# The /dr-quick mutating path emits a stage snapshot labeled `quick`.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
WRITER_LIB="${REPO_ROOT}/scripts/lib/snapshot-writer.sh"
QUICK_MD="${REPO_ROOT}/commands/dr-quick.md"

setup() {
    export TMPROOT="$BATS_TEST_TMPDIR/fake-repo"
    mkdir -p "$TMPROOT"
    export BODY="$BATS_TEST_TMPDIR/body.txt"
    printf 'synthetic quick-stage snapshot\n' > "$BODY"
    # shellcheck source=/dev/null
    . "$WRITER_LIB"
}

@test "quick producer stage is accepted and written to frontmatter" {
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task QCK-0001 \
        --stage quick \
        --command /dr-quick \
        --captured-by agent \
        --recommended-next /dr-status \
        --body-file "$BODY"
    [ "$status" -eq 0 ]
    local snap="$TMPROOT/datarim/snapshots/QCK-0001.snapshot.md"
    [ -f "$snap" ]
    grep -q '^stage: quick$' "$snap"
    grep -q '^command: /dr-quick$' "$snap"
}

@test "quick command and writer stage contract agree" {
    grep -Fq '`stage: quick`, `command: /dr-quick`' "$QUICK_MD"
    _snapshot_validate_stage quick
}

@test "every declared snapshot producer stage is accepted by the writer" {
    local producer_files producer_count=0 file section stage_line stage command_name
    producer_files="$(rg -l '^## Stage Snapshot Emission' "$REPO_ROOT/commands" | sort)"
    [ -n "$producer_files" ]
    while IFS= read -r file; do
        section="$(sed -n '/^## Stage Snapshot Emission/,$p' "$file")"
        stage_line="$(printf '%s\n' "$section" | grep -m1 -E 'stage`: `|stage: [[:alpha:]]')"
        stage="$(printf '%s\n' "$stage_line" | sed -E 's/.*stage`?:? *`?([[:alpha:]-]+)`?.*/\1/')"
        command_name="${file##*/}"
        command_name="${command_name#dr-}"
        command_name="${command_name%.md}"
        [ -n "$stage" ]
        [[ "$section" == *"/dr-${command_name}"* ]]
        _snapshot_validate_stage "$stage"
        producer_count=$((producer_count + 1))
    done <<< "$producer_files"
    [ "$producer_count" -eq 9 ]
}

@test "unknown stage remains rejected" {
    run write_stage_snapshot \
        --root "$TMPROOT" \
        --task QCK-0002 \
        --stage unsupported \
        --command /dr-quick \
        --captured-by agent \
        --recommended-next /dr-status \
        --body-file "$BODY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid stage unsupported"* ]]
}
