#!/usr/bin/env bats
# kb-backup.bats — pre-overwrite backup primitive for critical KB files.
#
# Contract: backup_critical_kb_file <repo-root> <relpath-under-datarim> copies
# the target to datarim/.backups/<basename>.<ISO-ts>.bak BEFORE it is overwritten,
# with FIFO rotation (DR_KB_BACKUP_KEEP, default 10), chmod 700 dir, and fail-soft
# semantics (never abort the caller). Generalizes the doctor's TUNE-0077
# backup convention. Maps to PRD V-AC-1/2/3.

BACKUP_LIB="$BATS_TEST_DIRNAME/../scripts/lib/kb-backup.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim"
    printf 'task index v1\n' > "$TMPROOT/datarim/tasks.md"
    printf 'BACKLOG ORIGINAL CONTENT\nline2\nline3\n' > "$TMPROOT/datarim/backlog.md"
}

teardown() {
    rm -rf "$TMPROOT"
}

# helper: count .bak files for a given basename
_count_baks() {
    find "$TMPROOT/datarim/.backups" -name "$1.*.bak" 2>/dev/null | wc -l | tr -d ' '
}

# --- V-AC-1: backup created before overwrite -------------------------------

@test "B1 backup of a critical file creates a timestamped .bak" {
    run bash -c '. "$1"; backup_critical_kb_file "$2" backlog.md' _ "$BACKUP_LIB" "$TMPROOT"
    [ "$status" -eq 0 ]
    [ "$(_count_baks backlog.md)" -eq 1 ]
}

@test "B2 the .bak holds the pre-overwrite content byte-identical" {
    bash -c '. "$1"; backup_critical_kb_file "$2" backlog.md' _ "$BACKUP_LIB" "$TMPROOT"
    local bak
    bak="$(find "$TMPROOT/datarim/.backups" -name 'backlog.md.*.bak' | head -1)"
    [ -n "$bak" ]
    run diff "$TMPROOT/datarim/backlog.md" "$bak"
    [ "$status" -eq 0 ]
}

@test "B3 backup dir is created chmod 700" {
    bash -c '. "$1"; backup_critical_kb_file "$2" backlog.md' _ "$BACKUP_LIB" "$TMPROOT"
    local mode
    mode="$(stat -f '%Lp' "$TMPROOT/datarim/.backups" 2>/dev/null || stat -c '%a' "$TMPROOT/datarim/.backups")"
    [ "$mode" = "700" ]
}

# --- V-AC-2: data-loss recovery (restore byte-identical) -------------------

@test "B4 after a simulated truncation, last backup restores byte-identical" {
    local original
    original="$(cat "$TMPROOT/datarim/backlog.md")"
    # take a backup, then truncate the file (the awk-with-/dev/null vector)
    bash -c '. "$1"; backup_critical_kb_file "$2" backlog.md' _ "$BACKUP_LIB" "$TMPROOT"
    : > "$TMPROOT/datarim/backlog.md"   # zero it
    [ ! -s "$TMPROOT/datarim/backlog.md" ]
    # restore from the most-recent backup
    local bak
    bak="$(find "$TMPROOT/datarim/.backups" -name 'backlog.md.*.bak' | sort | tail -1)"
    cp "$bak" "$TMPROOT/datarim/backlog.md"
    [ "$(cat "$TMPROOT/datarim/backlog.md")" = "$original" ]
}

# --- V-AC-3: FIFO rotation cap ---------------------------------------------

@test "B5 rotation cap evicts the oldest beyond DR_KB_BACKUP_KEEP" {
    # keep=3; write 5 distinct versions → at most 3 .bak retained
    for i in 1 2 3 4 5; do
        printf 'version %s\n' "$i" > "$TMPROOT/datarim/backlog.md"
        DR_KB_BACKUP_KEEP=3 bash -c '. "$1"; backup_critical_kb_file "$2" backlog.md' \
            _ "$BACKUP_LIB" "$TMPROOT"
        # ensure distinct timestamps (ISO seconds granularity)
        sleep 1
    done
    [ "$(_count_baks backlog.md)" -le 3 ]
    [ "$(_count_baks backlog.md)" -eq 3 ]
}

@test "B6 default keep is 10" {
    for i in $(seq 1 12); do
        printf 'v%s\n' "$i" > "$TMPROOT/datarim/backlog.md"
        bash -c '. "$1"; backup_critical_kb_file "$2" backlog.md' _ "$BACKUP_LIB" "$TMPROOT"
        sleep 1
    done
    [ "$(_count_baks backlog.md)" -eq 10 ]
}

# --- fail-soft + allowlist + safety ----------------------------------------

@test "B7 non-existent target is a no-op success (nothing to back up)" {
    run bash -c '. "$1"; backup_critical_kb_file "$2" activeContext.md' _ "$BACKUP_LIB" "$TMPROOT"
    [ "$status" -eq 0 ]
    [ "$(_count_baks activeContext.md)" -eq 0 ]
}

@test "B8 empty target is a no-op success (nothing worth backing up)" {
    : > "$TMPROOT/datarim/activeContext.md"
    run bash -c '. "$1"; backup_critical_kb_file "$2" activeContext.md' _ "$BACKUP_LIB" "$TMPROOT"
    [ "$status" -eq 0 ]
    [ "$(_count_baks activeContext.md)" -eq 0 ]
}

@test "B9 path traversal in relpath is refused (no escape outside datarim/)" {
    run bash -c '. "$1"; backup_critical_kb_file "$2" "../../etc/passwd"' _ "$BACKUP_LIB" "$TMPROOT"
    # fail-soft: returns 0 but performs NO copy outside the tree
    [ "$status" -eq 0 ]
    [ ! -d "$TMPROOT/datarim/.backups" ] || [ "$(find "$TMPROOT/datarim/.backups" -type f | wc -l | tr -d ' ')" -eq 0 ]
}

@test "B10 fail-soft: unwritable backup dir does not abort (returns 0)" {
    # pre-create .backups as a read-only dir so mkdir/cp inside fails
    mkdir -p "$TMPROOT/datarim/.backups"
    chmod 500 "$TMPROOT/datarim/.backups"
    run bash -c '. "$1"; backup_critical_kb_file "$2" backlog.md' _ "$BACKUP_LIB" "$TMPROOT"
    chmod 700 "$TMPROOT/datarim/.backups" 2>/dev/null || true
    [ "$status" -eq 0 ]
}

@test "B11 a caller-supplied non-allowlist path under datarim/ is still backed up" {
    # the contract allows any path under datarim/ supplied by an internal caller
    printf 'some state\n' > "$TMPROOT/datarim/systemPatterns.md"
    run bash -c '. "$1"; backup_critical_kb_file "$2" systemPatterns.md' _ "$BACKUP_LIB" "$TMPROOT"
    [ "$status" -eq 0 ]
    [ "$(_count_baks systemPatterns.md)" -eq 1 ]
}

# --- allowlist helper (used by the hook enforcement layer) ------------------

@test "B12 kb_is_critical_basename accepts allowlisted files" {
    run bash -c '. "$1"; kb_is_critical_basename backlog.md' _ "$BACKUP_LIB"
    [ "$status" -eq 0 ]
    run bash -c '. "$1"; kb_is_critical_basename tasks.md' _ "$BACKUP_LIB"
    [ "$status" -eq 0 ]
}

@test "B13 kb_is_critical_basename rejects non-allowlisted files" {
    run bash -c '. "$1"; kb_is_critical_basename systemPatterns.md' _ "$BACKUP_LIB"
    [ "$status" -ne 0 ]
    run bash -c '. "$1"; kb_is_critical_basename README.md' _ "$BACKUP_LIB"
    [ "$status" -ne 0 ]
}
