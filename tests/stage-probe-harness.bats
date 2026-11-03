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

# Per-test unique TASK-ID plus an owned temporary root keeps journal paths
# isolated from shared /tmp state.
generate_task_id() {
    # `%04d` PADS to four digits but does not CAP: $RANDOM reaches 32767, so
    # roughly two runs in three produced a five-digit ID. That was tolerated by
    # the old snapshot-writer regex (`[0-9]{4,5}`) and is rejected by the
    # canonical framework pattern (`[0-9]{4}`, per scripts/lib/schema-regex.sh and
    # datarim-doctor.sh) that the writer was realigned to. The fixture, not the
    # regex, was wrong: a four-digit ID is the contract everywhere else.
    printf 'TESTX-%04d' "$(( RANDOM % 10000 ))"
}

setup() {
    TASK_ID="$(generate_task_id)" || return 1
    PROBE_TMP_ROOT="$(mktemp -d "${BATS_TEST_TMPDIR}/stage-probe-root.XXXXXX")" || return 1
    chmod 0700 "$PROBE_TMP_ROOT" || return 1
    export TMPDIR="$PROBE_TMP_ROOT"
    HARNESS_DIR="${TMPDIR}/datarim-test-${TASK_ID}"
    FAKE_ROOT="$(mktemp -d "${BATS_TEST_TMPDIR}/fake-repo.XXXX")" || return 1
    mkdir -p "${FAKE_ROOT}/datarim/snapshots" || return 1
    BODY="$(mktemp "${BATS_TEST_TMPDIR}/body.XXXX")" || return 1
    OPTS="$(mktemp "${BATS_TEST_TMPDIR}/opts.XXXX")" || return 1
    printf '/dr-qa %s | placeholder\n' "$TASK_ID" > "$OPTS" || return 1
}

teardown() {
    if [ -n "${PROBE_TMP_ROOT:-}" ] && [ -d "$PROBE_TMP_ROOT" ]; then
        rm -rf -- "$PROBE_TMP_ROOT" || return 1
    fi
}

# ─── init ────────────────────────────────────────────────────────────────

@test "U1 init creates dir mode 0700 + payload + journal" {
    run "$INIT" "$TASK_ID" || return 1
    [ "$status" -eq 0 ] || return 1
    [ -d "$HARNESS_DIR" ] || return 1
    [ -f "$HARNESS_DIR/payload.txt" ] || return 1
    [ -f "$HARNESS_DIR/journal.md" ] || return 1
    # GNU stat (`-c`) and BSD stat (`-f`) take different format flags. On
    # Linux, `stat -f '%Lp'` silently means `--file-system '%Lp'` and prints
    # a multi-line filesystem dump with exit 0, so a naive OR-chain never
    # reaches `-c`. Pick the right flavour by OS first.
    if stat --version >/dev/null 2>&1; then
        mode=$(stat -c '%a' "$HARNESS_DIR") || return 1
    else
        mode=$(stat -f '%Lp' "$HARNESS_DIR") || return 1
    fi
    case "$mode" in 700|0700) ;; *) printf 'unexpected mode %s\n' "$mode" >&2; false ;; esac
    grep -q "^init · .* · TASK-ID=${TASK_ID}\$" "$HARNESS_DIR/journal.md" || return 1
}

@test "U2 init rejects malformed TASK-ID" {
    run "$INIT" "not-a-task-id" || return 1
    [ "$status" -eq 2 ] || return 1
}

@test "U3 init refuses symlink target" {
    SAFE_TARGET="$(mktemp -d "${BATS_TEST_TMPDIR}/decoy.XXXX")" || return 1
    ln -s "$SAFE_TARGET" "$HARNESS_DIR" || return 1
    run "$INIT" "$TASK_ID" || return 1
    [ "$status" -eq 1 ] || return 1
    # symlink remained untouched
    [ -L "$HARNESS_DIR" ] || return 1
    rm -f "$HARNESS_DIR" || return 1
}

# ─── writer journal hook ────────────────────────────────────────────────

@test "U4 writer appends header-present:y when body has Stage Header" {
    "$INIT" "$TASK_ID" || return 1
    printf '**%s · Sample Title**\n\nBody content here.\n' "$TASK_ID" > "$BODY" || return 1
    bash "$WRAPPER" \
        --root "$FAKE_ROOT" --task "$TASK_ID" --stage do --command /dr-do \
        --captured-by agent --recommended-next "/dr-qa $TASK_ID" \
        --options-file "$OPTS" --body-file "$BODY" || return 1
    grep -qE "^do · .* · header-present:y · snapshot-written:y · cta-footer:n · snapshot-sha:" "$HARNESS_DIR/journal.md" || return 1
}

@test "U5 writer appends header-present:n when body lacks header" {
    "$INIT" "$TASK_ID" || return 1
    printf 'Body without header\n' > "$BODY" || return 1
    bash "$WRAPPER" \
        --root "$FAKE_ROOT" --task "$TASK_ID" --stage do --command /dr-do \
        --captured-by agent --recommended-next "/dr-qa $TASK_ID" \
        --options-file "$OPTS" --body-file "$BODY" || return 1
    grep -qE "^do · .* · header-present:n · snapshot-written:y" "$HARNESS_DIR/journal.md" || return 1
}

@test "U6 writer appends cta-footer:y when body has Cyrillic CTA marker" {
    "$INIT" "$TASK_ID" || return 1
    printf '**%s · Title**\n\nBody.\n\nСледующий шаг — %s\n' "$TASK_ID" "$TASK_ID" > "$BODY" || return 1
    bash "$WRAPPER" \
        --root "$FAKE_ROOT" --task "$TASK_ID" --stage qa --command /dr-qa \
        --captured-by agent --recommended-next "/dr-archive $TASK_ID" \
        --options-file "$OPTS" --body-file "$BODY" || return 1
    grep -qE "^qa · .* · header-present:y · snapshot-written:y · cta-footer:y" "$HARNESS_DIR/journal.md" || return 1
}

# ─── cleanup ────────────────────────────────────────────────────────────

@test "U7 cleanup removes existing dir" {
    "$INIT" "$TASK_ID" || return 1
    [ -d "$HARNESS_DIR" ] || return 1
    run "$CLEANUP" "$TASK_ID" || return 1
    [ "$status" -eq 0 ] || return 1
    [ ! -d "$HARNESS_DIR" ] || return 1
}

@test "U8 cleanup is no-op on missing dir" {
    run "$CLEANUP" "$TASK_ID" || return 1
    [ "$status" -eq 0 ] || return 1
}

@test "U9 cleanup refuses symlink target" {
    SAFE_TARGET="$(mktemp -d "${BATS_TEST_TMPDIR}/decoy.XXXX")" || return 1
    ln -s "$SAFE_TARGET" "$HARNESS_DIR" || return 1
    run "$CLEANUP" "$TASK_ID" || return 1
    [ "$status" -eq 1 ] || return 1
    [ -L "$HARNESS_DIR" ] || return 1
    [ -d "$SAFE_TARGET" ] || return 1
    rm -f "$HARNESS_DIR" || return 1
}

# ─── wrapper integration ────────────────────────────────────────────────

@test "I1 wrapper writes snapshot file under bash" {
    printf '**%s · Title**\n\nBody.\n' "$TASK_ID" > "$BODY" || return 1
    run bash "$WRAPPER" \
        --root "$FAKE_ROOT" --task "$TASK_ID" --stage plan --command /dr-plan \
        --captured-by agent --recommended-next "/dr-do $TASK_ID" \
        --options-file "$OPTS" --body-file "$BODY" || return 1
    [ "$status" -eq 0 ] || return 1
    [ -f "${FAKE_ROOT}/datarim/snapshots/${TASK_ID}.snapshot.md" ] || return 1
    bytes=$(wc -c < "${FAKE_ROOT}/datarim/snapshots/${TASK_ID}.snapshot.md")
    [ "$bytes" -gt 100 ] || return 1
}
