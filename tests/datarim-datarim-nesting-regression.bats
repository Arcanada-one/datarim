#!/usr/bin/env bats
# datarim-datarim-nesting-regression.bats — reproduce + fix the nested
# datarim/datarim/ vector in the stage-snapshot writer.
#
# Symptom: invoking the writer with a --root that already points at (or inside)
# a datarim/ dir made it build "$root/datarim/snapshots" → datarim/datarim/snapshots/.
# Fix: snapshot-writer sources the canonical resolver and rejects a nested root
# via assert_not_nested_datarim. Maps to PRD V-AC-5.

WRAPPER="$BATS_TEST_DIRNAME/../dev-tools/snapshot-writer-wrapper.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim"
    printf '# Tasks\n' > "$TMPROOT/datarim/tasks.md"
    printf '# Backlog\n' > "$TMPROOT/datarim/backlog.md"
    mkdir -p "$TMPROOT/spaces/aether/code"
    BODY="$(mktemp)"
    printf '**TUNE-0001 · demo**\n\nbody\n' > "$BODY"
    OPTS="$(mktemp)"
    printf '/dr-qa TUNE-0001\n' > "$OPTS"
}

teardown() {
    rm -rf "$TMPROOT" "$BODY" "$OPTS"
}

_run_writer() {
    run bash "$WRAPPER" \
        --root "$1" --task TUNE-0001 --stage do --command /dr-do \
        --captured-by agent --recommended-next /dr-qa \
        --options-file "$OPTS" --body-file "$BODY"
}

# --- canonical path: a correct repo-root writes to datarim/snapshots/ -------

@test "G1 correct repo-root writes the canonical datarim/snapshots/ path" {
    _run_writer "$TMPROOT"
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/datarim/snapshots/TUNE-0001.snapshot.md" ]
    [ ! -e "$TMPROOT/datarim/datarim" ]
}

# --- the bug: a nested --root must NOT create datarim/datarim/ --------------

@test "G2 a nested --root (=<repo>/datarim) is rejected, no datarim/datarim/" {
    _run_writer "$TMPROOT/datarim"
    # writer must refuse rather than create datarim/datarim/snapshots/
    [ "$status" -ne 0 ]
    [ ! -e "$TMPROOT/datarim/datarim" ]
}

@test "G3 invoking from a deeply nested cwd still writes the canonical path" {
    # the space-layout case: cwd is nested, --root passed is repo-root
    run bash -c 'cd "$1" && bash "$2" \
        --root "$3" --task TUNE-0001 --stage do --command /dr-do \
        --captured-by agent --recommended-next /dr-qa \
        --options-file "$4" --body-file "$5"' \
        _ "$TMPROOT/spaces/aether/code" "$WRAPPER" "$TMPROOT" "$OPTS" "$BODY"
    [ "$status" -eq 0 ]
    [ -f "$TMPROOT/datarim/snapshots/TUNE-0001.snapshot.md" ]
    [ ! -e "$TMPROOT/datarim/datarim" ]
}

# --- guard unit: assert_not_nested_datarim is wired into the writer ---------

@test "G4 the writer sources the canonical resolver (no inline walk-up)" {
    grep -q 'resolve-datarim-root.sh' "$BATS_TEST_DIRNAME/../scripts/lib/snapshot-writer.sh"
}
