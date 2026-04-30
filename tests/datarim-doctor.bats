#!/usr/bin/env bats
# datarim-doctor.bats — TUNE-0071 thin-schema migration tool

DOCTOR="$BATS_TEST_DIRNAME/../scripts/datarim-doctor.sh"
FIXTURES="$BATS_TEST_DIRNAME/fixtures/datarim-doctor"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks" "$TMPROOT/documentation/archive/framework"
}

teardown() {
    rm -rf "$TMPROOT"
}

# --- Compliance detection (dry-run) -----------------------------------------

@test "T1 dry-run on legacy tasks.md → exit 1 + finding count" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 1 ]
    [[ "$output" == *"finding"* ]] || [[ "$output" == *"non-compliant"* ]]
}

@test "T2 dry-run on compliant tasks.md → exit 0" {
    cp "$FIXTURES/compliant-tasks.md" "$TMPROOT/datarim/tasks.md"
    # Description files must exist for entries referenced
    : > "$TMPROOT/datarim/tasks/TUNE-0071-task-description.md"
    : > "$TMPROOT/datarim/tasks/LEGACY-0001-task-description.md"
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ]
}

@test "T3 dry-run on empty datarim/ → exit 0" {
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ]
}

@test "T4 quiet mode produces no stdout" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --quiet
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

# --- Migration (--fix) -------------------------------------------------------

@test "T5 --fix on legacy tasks.md produces compliant one-liner" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    # tasks.md must contain one-liner format
    grep -qE '^- TUNE-0071 · in_progress · P[0-3] · L[1-4] · .+ → tasks/TUNE-0071-task-description\.md$' \
        "$TMPROOT/datarim/tasks.md"
    grep -qE '^- LEGACY-0001 · in_progress · P[0-3] · L[1-4] · .+ → tasks/LEGACY-0001-task-description\.md$' \
        "$TMPROOT/datarim/tasks.md"
}

@test "T6 --fix creates description file for each task" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/datarim/tasks/TUNE-0071-task-description.md" ]
    [ -f "$TMPROOT/datarim/tasks/LEGACY-0001-task-description.md" ]
}

@test "T7 description file has YAML frontmatter with required keys" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    "$DOCTOR" --root="$TMPROOT/datarim" --fix >/dev/null
    desc="$TMPROOT/datarim/tasks/TUNE-0071-task-description.md"
    head -1 "$desc" | grep -q '^---$'
    grep -qE '^id: TUNE-0071$' "$desc"
    grep -qE '^status: in_progress$' "$desc"
    grep -qE '^complexity: L3$' "$desc"
    grep -qE '^priority: P1$' "$desc"
}

@test "T8 --fix idempotent: second run produces no changes" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    "$DOCTOR" --root="$TMPROOT/datarim" --fix >/dev/null
    cp -r "$TMPROOT/datarim" "$TMPROOT/datarim.first"
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    diff -r "$TMPROOT/datarim" "$TMPROOT/datarim.first" >&2
    [ "$(diff -r "$TMPROOT/datarim" "$TMPROOT/datarim.first" 2>&1 | wc -l | tr -d ' ')" = "0" ]
}

@test "T9 --fix on legacy backlog.md produces one-liner pending entries" {
    cp "$FIXTURES/legacy-backlog.md" "$TMPROOT/datarim/backlog.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    grep -qE '^- TUNE-0099 · pending · P[0-3] · L[1-4] · .+ → tasks/TUNE-0099-task-description\.md$' \
        "$TMPROOT/datarim/backlog.md"
    grep -qE '^- INFRA-0099 · pending · P[0-3] · L[1-4] · .+ → tasks/INFRA-0099-task-description\.md$' \
        "$TMPROOT/datarim/backlog.md"
}

@test "T10 --fix deletes legacy progress.md after preserving data" {
    cp "$FIXTURES/legacy-progress.md" "$TMPROOT/datarim/progress.md"
    cp "$FIXTURES/legacy-activeContext.md" "$TMPROOT/datarim/activeContext.md"
    # Pre-create archive files so doctor knows data is preserved
    : > "$TMPROOT/documentation/archive/framework/archive-TUNE-0069.md"
    : > "$TMPROOT/documentation/archive/framework/archive-TUNE-0070.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    [ ! -f "$TMPROOT/datarim/progress.md" ]
}

# --- Security ---------------------------------------------------------------

@test "T11 path traversal attempt in tasks.md → exit 4" {
    cp "$FIXTURES/crafted-traversal.md" "$TMPROOT/datarim/tasks.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 4 ]
    [[ "$output" == *"traversal"* ]] || [[ "$output" == *"security"* ]] || [[ "$output" == *"reject"* ]]
}

@test "T12 ROOT outside cwd resolves correctly via canonicalise" {
    # absolute path acceptable
    run "$DOCTOR" --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ]
    # nonexistent root → usage error
    run "$DOCTOR" --root="/tmp/nonexistent-doctor-$$"
    [ "$status" -ne 0 ]
}

# --- Regex compliance --------------------------------------------------------

@test "T13 generated lines match canonical regex" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    "$DOCTOR" --root="$TMPROOT/datarim" --fix >/dev/null
    # Every non-empty bullet line must match the canonical schema
    while IFS= read -r line; do
        [[ "$line" =~ ^-\ [A-Z]{2,10}-[0-9]{4}\ ·\ (in_progress|blocked|not_started|pending|blocked-pending|cancelled)\ ·\ P[0-3]\ ·\ L[1-4]\ ·\ .{1,80}\ →\ tasks/[A-Z]{2,10}-[0-9]{4}-task-description\.md$ ]]
    done < <(grep -E '^- [A-Z]+-' "$TMPROOT/datarim/tasks.md")
}

# --- CLI / UX ----------------------------------------------------------------

@test "T14 --help prints usage and exit 0" {
    run "$DOCTOR" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--fix"* ]]
    [[ "$output" == *"--root"* ]]
}

@test "T15 unknown flag → exit 64 (usage error)" {
    run "$DOCTOR" --bogus-flag
    [ "$status" -eq 64 ]
}

# --- TUNE-0077: data-loss safety contract -----------------------------------

@test "T16 (TUNE-0077) --fix creates pre-write tarball backup of datarim/" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    BACKUP_DIR="$TMPROOT/backup-out"
    mkdir -p "$BACKUP_DIR"
    DATARIM_DOCTOR_BACKUP_DIR="$BACKUP_DIR" run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    # Exactly one tarball expected, named datarim-backup-*.tgz
    n="$(find "$BACKUP_DIR" -name 'datarim-backup-*.tgz' | wc -l | tr -d ' ')"
    [ "$n" = "1" ]
    # Backup tarball must contain the original tasks.md (pre-fix state)
    tarball="$(find "$BACKUP_DIR" -name 'datarim-backup-*.tgz')"
    tar tzf "$tarball" | grep -q 'tasks.md'
}

@test "T17 (TUNE-0077) --fix backup file mode is 0600 (umask 077)" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    BACKUP_DIR="$TMPROOT/backup-out"
    mkdir -p "$BACKUP_DIR"
    DATARIM_DOCTOR_BACKUP_DIR="$BACKUP_DIR" "$DOCTOR" --root="$TMPROOT/datarim" --fix >/dev/null
    tarball="$(find "$BACKUP_DIR" -name 'datarim-backup-*.tgz')"
    mode="$(stat -f '%Lp' "$tarball" 2>/dev/null || stat -c '%a' "$tarball" 2>/dev/null)"
    [ "$mode" = "600" ]
}

@test "T18 (TUNE-0077) post-fix invariant: emitted_count >= parsed_count" {
    # Synthetic 3-task fixture; after --fix all 3 IDs MUST appear as one-liners
    cat > "$TMPROOT/datarim/backlog.md" <<'EOF'
# Backlog

## Pending

### TUNE-9001: Safety check 1

- **Status:** pending
- **Priority:** P2
- **Complexity:** Level 1

### TUNE-9002: Safety check 2

- **Status:** pending
- **Priority:** P3
- **Complexity:** Level 2

### TUNE-9003: Safety check 3

- **Status:** pending
- **Priority:** P2
- **Complexity:** Level 1
EOF
    "$DOCTOR" --root="$TMPROOT/datarim" --fix >/dev/null
    n="$(grep -c '^- TUNE-900' "$TMPROOT/datarim/backlog.md")"
    [ "$n" = "3" ]
}

@test "T19 (TUNE-0077) printf hardening: no 'printf \"\$' patterns in script" {
    # Bug C class: printf "$line" misparses '-' prefix as flag
    ! grep -nE 'printf "\$' "$DOCTOR"
}

@test "T20 (TUNE-0077) --fix on body starting with '-' produces clean stderr" {
    # Body line starting with '-' must not trigger 'printf: invalid option' errors
    cat > "$TMPROOT/datarim/tasks.md" <<'EOF'
# Tasks

## Active

### TUNE-9100: Body with leading dash

- **Status:** in_progress
- **Priority:** P2
- **Complexity:** Level 1

#### Overview

- bullet line that starts with a dash and could trigger printf flag parsing
- another such bullet
EOF
    run "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    # No 'invalid option' or '-:' printf errors in stderr
    [[ "$output" != *"invalid option"* ]]
    [[ "$output" != *"printf:"* ]] || [[ "$output" != *"-:"* ]]
}

@test "T21 (TUNE-0077) --fix prints backup path in stdout summary" {
    cp "$FIXTURES/legacy-tasks.md" "$TMPROOT/datarim/tasks.md"
    BACKUP_DIR="$TMPROOT/backup-out"
    mkdir -p "$BACKUP_DIR"
    run env DATARIM_DOCTOR_BACKUP_DIR="$BACKUP_DIR" "$DOCTOR" --root="$TMPROOT/datarim" --fix
    [ "$status" -eq 0 ]
    [[ "$output" == *"backup"* ]] || [[ "$output" == *"Backup"* ]]
    [[ "$output" == *"datarim-backup-"* ]]
}
