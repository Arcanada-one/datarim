#!/usr/bin/env bats
#
# TUNE-0254 F5 -- truncation MUST NOT leave a partial UTF-8 codepoint at the
# byte boundary. head -c $N is byte-accurate but codepoint-ignorant; cutting
# mid-sequence yields a file that downstream utf-8-strict tools reject.
#
# Fix: writer post-processes the truncated chunk via iconv -c (POSIX,
# available on macOS libiconv and Linux glibc) to drop any trailing
# incomplete sequence.
#
# Validator in tests uses python3 .decode('utf-8') strict mode rather than
# iconv -f UTF-8 -t UTF-8 because macOS libiconv prints a benign
# "Inappropriate ioctl for device" diagnostic that confuses bats teardown.

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

assert_valid_utf8() {
    local file="$1"
    # iconv -c (POSIX) drops invalid/incomplete sequences; on a valid file the
    # cleansed-byte-count equals the original. Diverged sizes => invalid UTF-8.
    # Avoids python3 stdin-binary reads which trip up bats output capture on
    # macOS when the file ends mid-multibyte-sequence.
    local original cleansed
    original="$(wc -c < "$file" | tr -d ' ')"
    cleansed="$(iconv -c -f UTF-8 -t UTF-8 < "$file" 2>/dev/null | wc -c | tr -d ' ')"
    [ "$original" -eq "$cleansed" ]
}

@test "f5a cjk body truncated to valid utf8" {
    local body="$BATS_TEST_TMPDIR/cjk.txt"
    # 3000 copies of 3-byte CJK U+4E00 = 9000 bytes; far exceeds 8192 cap.
    python3 -c 'import sys; sys.stdout.write("一" * 3000)' > "$body"

    write_stage_snapshot \
        --root "$TMPROOT" --task TUNE-0254 --stage plan --command /dr-plan \
        --captured-by agent --recommended-next /dr-do \
        --options-file "$OPTIONS" --body-file "$body"

    local snap="$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md"
    local size
    size="$(wc -c < "$snap" | tr -d ' ')"
    [ "$size" -le 8192 ]
    assert_valid_utf8 "$snap"
    grep -q 'snapshot-truncated' "$snap"
}

@test "f5b emoji body truncated to valid utf8" {
    local body="$BATS_TEST_TMPDIR/emoji.txt"
    # 2200 copies of 4-byte emoji U+1F30D = 8800 bytes; exceeds 8192 cap.
    python3 -c 'import sys; sys.stdout.write("\U0001f30d" * 2200)' > "$body"

    write_stage_snapshot \
        --root "$TMPROOT" --task TUNE-0254 --stage plan --command /dr-plan \
        --captured-by agent --recommended-next /dr-do \
        --options-file "$OPTIONS" --body-file "$body"

    local snap="$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md"
    local size
    size="$(wc -c < "$snap" | tr -d ' ')"
    [ "$size" -le 8192 ]
    assert_valid_utf8 "$snap"
    grep -q 'snapshot-truncated' "$snap"
}

@test "f5c ascii body still passes regression guard" {
    local body="$BATS_TEST_TMPDIR/ascii.txt"
    python3 -c 'print("A" * 10000)' > "$body"

    write_stage_snapshot \
        --root "$TMPROOT" --task TUNE-0254 --stage plan --command /dr-plan \
        --captured-by agent --recommended-next /dr-do \
        --options-file "$OPTIONS" --body-file "$body"

    local snap="$TMPROOT/datarim/snapshots/TUNE-0254.snapshot.md"
    local size
    size="$(wc -c < "$snap" | tr -d ' ')"
    [ "$size" -le 8192 ]
    assert_valid_utf8 "$snap"
}
