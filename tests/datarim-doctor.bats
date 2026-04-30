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
