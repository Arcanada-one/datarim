#!/usr/bin/env bats
# doctor-root-contract.bats — --root is REPO-ROOT canonical (TUNE-0341).
#
# Before this task --root meant the datarim/ dir itself in datarim-doctor.sh,
# while every pipeline caller (/dr-init Step 2.4, /dr-doctor) passes the
# REPO-ROOT. The mismatch meant the docs→history migration silently never
# fired through the pipeline. This suite locks the canonical contract:
#
#   --root=<repo-root>     → canonical; doctor derives <repo-root>/datarim
#   --root=<repo>/datarim  → legacy; transition shim normalises + warns
#
# Maps to PRD V-AC-6 (unified --root) and V-AC-7 (docs→history fires via pipeline).

DOCTOR="$BATS_TEST_DIRNAME/../scripts/datarim-doctor.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/docs" "$TMPROOT/documentation/architecture"
    printf '# Tasks\n\n## Active\n' > "$TMPROOT/datarim/tasks.md"
    printf '# Backlog\n\n## Pending\n' > "$TMPROOT/datarim/backlog.md"
    printf '# Active Context\n\n## Active Tasks\n' > "$TMPROOT/datarim/activeContext.md"
    printf 'evolution\nline2\n' > "$TMPROOT/datarim/docs/evolution-log.md"
    printf '/datarim/\n' > "$TMPROOT/.gitignore"
    export DATARIM_DOCTOR_BACKUP_DIR="$TMPROOT/.bak"
}

teardown() {
    rm -rf "$TMPROOT"
    unset DATARIM_DOCTOR_BACKUP_DIR
}

# --- canonical repo-root form (the way the pipeline invokes the doctor) -----

@test "C1 --root=<repo-root> detects docs/ ledger (exit 1 dry-run)" {
    run "$DOCTOR" --root="$TMPROOT" --scope=history
    [ "$status" -eq 1 ]
}

@test "C2 --root=<repo-root> --fix migrates docs/ → history/" {
    run "$DOCTOR" --root="$TMPROOT" --scope=history --fix
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/datarim/history/evolution-log.md" ]
    [ ! -d "$TMPROOT/datarim/docs" ]
}

@test "C3 --root=<repo-root> --fix preserves ledger content byte-identical" {
    local before
    before="$(cat "$TMPROOT/datarim/docs/evolution-log.md")"
    "$DOCTOR" --root="$TMPROOT" --scope=history --fix >/dev/null
    [ "$(cat "$TMPROOT/datarim/history/evolution-log.md")" = "$before" ]
}

@test "C4 --root=<repo-root> on a compliant KB exits 0" {
    # no docs/ → already compliant
    rm -rf "$TMPROOT/datarim/docs"
    run "$DOCTOR" --root="$TMPROOT" --scope=history
    [ "$status" -eq 0 ]
}

# --- legacy datarim-dir form: transition shim normalises + warns ------------

@test "C5 legacy --root=<repo>/datarim still works (normalised), warns on stderr" {
    run "$DOCTOR" --root="$TMPROOT/datarim" --scope=history --fix
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/datarim/history/evolution-log.md" ]
    [ ! -d "$TMPROOT/datarim/datarim" ]
    [[ "$output" == *legacy* ]] || [[ "$output" == *repo-root* ]] || [[ "$output" == *normalis* ]]
}

@test "C6 legacy form does NOT create a nested datarim/datarim/" {
    "$DOCTOR" --root="$TMPROOT/datarim" --scope=all --fix >/dev/null 2>&1 || true
    [ ! -e "$TMPROOT/datarim/datarim" ]
}

# --- resolver default: nested cwd, no --root, finds repo-root ---------------

@test "C7 no --root from nested cwd resolves repo-root (not the nested dir)" {
    mkdir -p "$TMPROOT/spaces/aether/code"
    command -v git >/dev/null && git -C "$TMPROOT" init -q
    run bash -c 'cd "$1" && "$2" --scope=history' "$TMPROOT/spaces/aether/code" "$DOCTOR"
    # detects the docs/ ledger at the real repo-root → exit 1 (dry-run finding)
    [ "$status" -eq 1 ]
}

# --- gitignore negation written under canonical form ------------------------

@test "C8 --root=<repo-root> --fix writes the .gitignore history negation" {
    "$DOCTOR" --root="$TMPROOT" --scope=history --fix >/dev/null
    grep -q '!/datarim/history/' "$TMPROOT/.gitignore"
}
