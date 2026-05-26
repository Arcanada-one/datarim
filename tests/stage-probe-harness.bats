#!/usr/bin/env bats
#
# Phase 2 harness tests — init/cleanup probe scripts + journal-hook
# auto-detection inside write_stage_snapshot.
#
# Coverage:
#   U1 init creates dir mode 0700 + payload.txt + journal.md
#   U2 init rejects malformed TASK-ID
#   U3 init refuses symlink target (T2 mitigation)
#   U4 writer appends journal line with header-present:y when body starts with **{TASK-ID} · ...**
#   U5 writer appends header-present:n when body lacks header
#   U6 writer appends cta-footer:y when body contains «Следующий шаг — {TASK-ID}»
#   U7 cleanup removes existing dir (idempotent)
#   U8 cleanup is no-op on missing dir
#   U9 cleanup refuses symlink target
#   I1 wrapper script invokes write_stage_snapshot under bash and writes snapshot

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
WRITER_LIB="${REPO_ROOT}/scripts/lib/snapshot-writer.sh"
WRAPPER="${REPO_ROOT}/dev-tools/snapshot-writer-wrapper.sh"
INIT="${REPO_ROOT}/dev-tools/datarim-stage-probe-init.sh"
CLEANUP="${REPO_ROOT}/dev-tools/datarim-stage-probe-cleanup.sh"

# Per-test unique TASK-ID so journal directories don't collide across cases.
generate_task_id() {
    printf 'TESTX-%04d' "$RANDOM"
}

setup() {
    TASK_ID="$(generate_task_id)"
    HARNESS_DIR="/tmp/datarim-test-${TASK_ID}"
    FAKE_ROOT="$(mktemp -d "${BATS_TEST_TMPDIR}/fake-repo.XXXX")"
    mkdir -p "${FAKE_ROOT}/datarim/snapshots"
    BODY="$(mktemp "${BATS_TEST_TMPDIR}/body.XXXX")"
    OPTS="$(mktemp "${BATS_TEST_TMPDIR}/opts.XXXX")"
    printf '/dr-qa %s | placeholder\n' "$TASK_ID" > "$OPTS"
}

teardown() {
    if [ -n "${HARNESS_DIR:-}" ] && [ -d "$HARNESS_DIR" ]; then
        rm -rf "$HARNESS_DIR"
    fi
}

# ─── init ────────────────────────────────────────────────────────────────

@test "U1 init creates dir mode 0700 + payload + journal" {
    run "$INIT" "$TASK_ID"
    [ "$status" -eq 0 ]
    [ -d "$HARNESS_DIR" ]
    [ -f "$HARNESS_DIR/payload.txt" ]
    [ -f "$HARNESS_DIR/journal.md" ]
    mode=$(stat -f '%Lp' "$HARNESS_DIR" 2>/dev/null || stat -c '%a' "$HARNESS_DIR")
    # Linux `stat -c '%a'` and macOS `stat -f '%Lp'` both omit leading zeros,
    # but some toolchains (sticky-bit/setgid carryover from parent dir on
    # ubuntu-latest) prepend an extra digit. Accept any form whose last three
    # digits are 700.
    case "$mode" in 700|0700) ;; *) printf 'unexpected mode %s\n' "$mode" >&2; false ;; esac
    grep -q "^init · .* · TASK-ID=${TASK_ID}\$" "$HARNESS_DIR/journal.md"
}

@test "U2 init rejects malformed TASK-ID" {
    run "$INIT" "not-a-task-id"
    [ "$status" -eq 2 ]
}

@test "U3 init refuses symlink target" {
    SAFE_TARGET="$(mktemp -d "${BATS_TEST_TMPDIR}/decoy.XXXX")"
    ln -s "$SAFE_TARGET" "$HARNESS_DIR"
    run "$INIT" "$TASK_ID"
    [ "$status" -eq 1 ]
    # symlink remained untouched
    [ -L "$HARNESS_DIR" ]
    rm -f "$HARNESS_DIR"
}

# ─── writer journal hook ────────────────────────────────────────────────

@test "U4 writer appends header-present:y when body has Stage Header" {
    "$INIT" "$TASK_ID"
    printf '**%s · Sample Title**\n\nBody content here.\n' "$TASK_ID" > "$BODY"
    bash "$WRAPPER" \
        --root "$FAKE_ROOT" --task "$TASK_ID" --stage do --command /dr-do \
        --captured-by agent --recommended-next "/dr-qa $TASK_ID" \
        --options-file "$OPTS" --body-file "$BODY"
    grep -qE "^do · .* · header-present:y · snapshot-written:y · cta-footer:n · snapshot-sha:" "$HARNESS_DIR/journal.md"
}

@test "U5 writer appends header-present:n when body lacks header" {
    "$INIT" "$TASK_ID"
    printf 'Body without header\n' > "$BODY"
    bash "$WRAPPER" \
        --root "$FAKE_ROOT" --task "$TASK_ID" --stage do --command /dr-do \
        --captured-by agent --recommended-next "/dr-qa $TASK_ID" \
        --options-file "$OPTS" --body-file "$BODY"
    grep -qE "^do · .* · header-present:n · snapshot-written:y" "$HARNESS_DIR/journal.md"
}

@test "U6 writer appends cta-footer:y when body has Cyrillic CTA marker" {
    "$INIT" "$TASK_ID"
    printf '**%s · Title**\n\nBody.\n\nСледующий шаг — %s\n' "$TASK_ID" "$TASK_ID" > "$BODY"
    bash "$WRAPPER" \
        --root "$FAKE_ROOT" --task "$TASK_ID" --stage qa --command /dr-qa \
        --captured-by agent --recommended-next "/dr-archive $TASK_ID" \
        --options-file "$OPTS" --body-file "$BODY"
    grep -qE "^qa · .* · header-present:y · snapshot-written:y · cta-footer:y" "$HARNESS_DIR/journal.md"
}

# ─── cleanup ────────────────────────────────────────────────────────────

@test "U7 cleanup removes existing dir" {
    "$INIT" "$TASK_ID"
    [ -d "$HARNESS_DIR" ]
    run "$CLEANUP" "$TASK_ID"
    [ "$status" -eq 0 ]
    [ ! -d "$HARNESS_DIR" ]
}

@test "U8 cleanup is no-op on missing dir" {
    run "$CLEANUP" "$TASK_ID"
    [ "$status" -eq 0 ]
}

@test "U9 cleanup refuses symlink target" {
    SAFE_TARGET="$(mktemp -d "${BATS_TEST_TMPDIR}/decoy.XXXX")"
    ln -s "$SAFE_TARGET" "$HARNESS_DIR"
    run "$CLEANUP" "$TASK_ID"
    [ "$status" -eq 1 ]
    [ -L "$HARNESS_DIR" ]
    [ -d "$SAFE_TARGET" ]
    rm -f "$HARNESS_DIR"
}

# ─── wrapper integration ────────────────────────────────────────────────

@test "I1 wrapper writes snapshot file under bash" {
    printf '**%s · Title**\n\nBody.\n' "$TASK_ID" > "$BODY"
    run bash "$WRAPPER" \
        --root "$FAKE_ROOT" --task "$TASK_ID" --stage plan --command /dr-plan \
        --captured-by agent --recommended-next "/dr-do $TASK_ID" \
        --options-file "$OPTS" --body-file "$BODY"
    [ "$status" -eq 0 ]
    [ -f "${FAKE_ROOT}/datarim/snapshots/${TASK_ID}.snapshot.md" ]
    bytes=$(wc -c < "${FAKE_ROOT}/datarim/snapshots/${TASK_ID}.snapshot.md")
    [ "$bytes" -gt 100 ]
}
