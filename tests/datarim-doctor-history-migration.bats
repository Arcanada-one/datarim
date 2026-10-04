#!/usr/bin/env bats
# datarim-doctor-history-migration.bats — ledger-dir retire pass (docs/ → history/)

DOCTOR="$BATS_TEST_DIRNAME/../scripts/datarim-doctor.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/docs" "$TMPROOT/documentation/architecture"
    # minimal compliant operational files so other passes are no-ops
    printf '# Tasks\n\n## Active\n' > "$TMPROOT/datarim/tasks.md"
    printf '# Backlog\n\n## Pending\n' > "$TMPROOT/datarim/backlog.md"
    printf '# Active Context\n\n## Active Tasks\n' > "$TMPROOT/datarim/activeContext.md"
    # seed three ledgers with distinct multi-line content for byte-compare
    printf 'evolution\nline2\nline3\n' > "$TMPROOT/datarim/docs/evolution-log.md"
    printf 'activity\nlineB\nlineC\n' > "$TMPROOT/datarim/docs/activity-log.md"
    printf 'patterns\nlineX\nlineY\n' > "$TMPROOT/datarim/docs/patterns.md"
    # an ADR with a task-id prefix (history-agnostic relocation strips it)
    printf '# ADR\ncontent\n' > "$TMPROOT/datarim/docs/ADR-TUNE-0014-cross-repo-atomicity.md"
    # consumer .gitignore at repo root with the wholesale datarim/ ignore
    printf '/datarim/\n' > "$TMPROOT/.gitignore"
}

teardown() {
    rm -rf "$TMPROOT"
}

# --- detection (dry-run) ----------------------------------------------------

@test "H1 dry-run detects docs/ ledgers → exit 1" {
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history
    [ "$status" -eq 1 ]
    [[ "$output" == *"evolution-log.md"* ]]
    [[ "$output" == *"history/"* ]]
}

@test "H2 dry-run flags the ADR for relocation" {
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history
    [ "$status" -eq 1 ]
    [[ "$output" == *"ADR"* ]]
    [[ "$output" == *"documentation/architecture"* ]]
}

# --- fix: move ledgers ------------------------------------------------------

@test "H3 --fix moves three ledgers to datarim/history/" {
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/datarim/history/evolution-log.md" ]
    [ -f "$TMPROOT/datarim/history/activity-log.md" ]
    [ -f "$TMPROOT/datarim/history/patterns.md" ]
}

@test "H4 --fix relocates ADR to documentation/architecture/ADR-0002-*" {
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/documentation/architecture/ADR-0002-cross-repo-atomicity.md" ]
    # original task-id-prefixed name is gone
    [ ! -f "$TMPROOT/datarim/docs/ADR-TUNE-0014-cross-repo-atomicity.md" ]
}

@test "H5 --fix removes the now-empty datarim/docs/ directory" {
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    [ "$status" -eq 0 ]
    [ ! -d "$TMPROOT/datarim/docs" ]
}

# --- losslessness -----------------------------------------------------------

@test "H6 ledger content is byte-identical after the move (no data loss)" {
    local before_evo before_act before_pat
    before_evo="$(cat "$TMPROOT/datarim/docs/evolution-log.md")"
    before_act="$(cat "$TMPROOT/datarim/docs/activity-log.md")"
    before_pat="$(cat "$TMPROOT/datarim/docs/patterns.md")"
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    [ "$status" -eq 0 ]
    [ "$(cat "$TMPROOT/datarim/history/evolution-log.md")" = "$before_evo" ]
    [ "$(cat "$TMPROOT/datarim/history/activity-log.md")" = "$before_act" ]
    [ "$(cat "$TMPROOT/datarim/history/patterns.md")" = "$before_pat" ]
}

# --- idempotency ------------------------------------------------------------

@test "H7 second --fix is a no-op (exit 0, no changes)" {
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    [ "$status" -eq 0 ]
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    [ "$status" -eq 0 ]
    # history files still present, docs/ still gone
    [ -f "$TMPROOT/datarim/history/evolution-log.md" ]
    [ ! -d "$TMPROOT/datarim/docs" ]
}

@test "H8 post-fix dry-run reports compliant (exit 0)" {
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    [ "$status" -eq 0 ]
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history
    [ "$status" -eq 0 ]
}

# --- gitignore negation written by the pass ---------------------------------

@test "H9 --fix appends the history negation block to consumer .gitignore" {
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    [ "$status" -eq 0 ]
    grep -qF '!/datarim/history/' "$TMPROOT/.gitignore"
    grep -qF '!/datarim/history/**' "$TMPROOT/.gitignore"
}

@test "H10 negation block is not duplicated on re-run (idempotent gitignore)" {
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    local n
    n="$(grep -cF '!/datarim/history/**' "$TMPROOT/.gitignore")"
    [ "$n" -eq 1 ]
}

# --- cleanup-safety (V-AC-7): never delete a ledger -------------------------

@test "H11 no deletion of ledgers — content survives at new path" {
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    [ "$status" -eq 0 ]
    # every ledger that existed in docs/ exists in history/ with content
    [ -s "$TMPROOT/datarim/history/evolution-log.md" ]
    [ -s "$TMPROOT/datarim/history/activity-log.md" ]
    [ -s "$TMPROOT/datarim/history/patterns.md" ]
}

# --- no docs/ dir → pass is a clean no-op -----------------------------------

@test "H12 fresh consumer without docs/ → dry-run + fix both exit 0" {
    rm -rf "$TMPROOT/datarim/docs"
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history
    [ "$status" -eq 0 ]
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    [ "$status" -eq 0 ]
}

# --- partial docs/ (only one ledger) ----------------------------------------

@test "H13 only evolution-log present → migrates just that file" {
    rm -f "$TMPROOT/datarim/docs/activity-log.md" \
          "$TMPROOT/datarim/docs/patterns.md" \
          "$TMPROOT/datarim/docs/ADR-TUNE-0014-cross-repo-atomicity.md"
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/datarim/history/evolution-log.md" ]
    [ ! -f "$TMPROOT/datarim/history/activity-log.md" ]
    [ ! -d "$TMPROOT/datarim/docs" ]
}
