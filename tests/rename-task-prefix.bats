#!/usr/bin/env bats
# rename-task-prefix.sh — repeatable, safe project-task-prefix rename.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/dev-tools/rename-task-prefix.sh"
    TREE="$(mktemp -d)"
    # A body with a target id, a look-alike longer prefix, and a second target.
    printf 'see TUNE-0001 and NEPTUNE-0007 and TUNE-0002 done\n' > "$TREE/body.md"
    printf 'frozen ref to TUNE-0002 must survive exclusion\n'   > "$TREE/note-TUNE-0002.md"
    printf 'archived\n'                                          > "$TREE/archive-TUNE-0001.md"
}

teardown() {
    [ -n "${TREE:-}" ] && rm -rf "$TREE"
}

# --- Dry-run mutates nothing ------------------------------------------------

@test "dry-run: plans changes, mutates nothing" {
    run "$SCRIPT" --old TUNE --new DATA --root "$TREE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry-run"* ]]
    # files untouched
    [ -f "$TREE/archive-TUNE-0001.md" ]
    run grep -q 'TUNE-0001' "$TREE/body.md"
    [ "$status" -eq 0 ]
}

# --- Apply rewrites bodies + renames files + sweep clean --------------------

@test "apply: rewrites body ids, renames file, leaves look-alike prefix alone" {
    run "$SCRIPT" --old TUNE --new DATA --root "$TREE" --apply
    [ "$status" -eq 0 ]
    # body: both anchored ids rewritten, NEPTUNE untouched
    run cat "$TREE/body.md"
    [[ "$output" == *"DATA-0001"* ]]
    [[ "$output" == *"DATA-0002"* ]]
    [[ "$output" == *"NEPTUNE-0007"* ]]
    [[ "$output" != *"TUNE-0001"* ]]
    # file renamed
    [ -f "$TREE/archive-DATA-0001.md" ]
    [ ! -f "$TREE/archive-TUNE-0001.md" ]
}

# --- Exclude keeps a frozen id untouched (body + filename) ------------------

@test "apply --exclude: frozen id survives in body and filename" {
    run "$SCRIPT" --old TUNE --new DATA --root "$TREE" --apply --exclude TUNE-0002
    [ "$status" -eq 0 ]
    # excluded id kept as-is
    [ -f "$TREE/note-TUNE-0002.md" ]
    run grep -q 'TUNE-0002' "$TREE/note-TUNE-0002.md"
    [ "$status" -eq 0 ]
    # body: TUNE-0001 rewritten, TUNE-0002 excluded (kept)
    run cat "$TREE/body.md"
    [[ "$output" == *"DATA-0001"* ]]
    [[ "$output" == *"TUNE-0002"* ]]
}

# --- Verification sweep fails when a directory still carries the prefix -----

@test "apply: residual (directory name) -> exit 1" {
    mkdir "$TREE/TUNE-0009"
    printf 'child\n' > "$TREE/TUNE-0009/inner.md"
    run "$SCRIPT" --old TUNE --new DATA --root "$TREE" --apply
    [ "$status" -eq 1 ]
    [[ "$output" == *"RESIDUAL TUNE-0009"* ]]
}

# --- quiet mode is machine-terse -------------------------------------------

@test "quiet: emits counts line" {
    run "$SCRIPT" --old TUNE --new DATA --root "$TREE" --quiet
    [ "$status" -eq 0 ]
    [[ "$output" == *"mode=dry-run"* ]]
    [[ "$output" == *"bodies="* ]]
    [[ "$output" == *"renames="* ]]
}

# --- Usage / validation errors ---------------------------------------------

@test "bad --old prefix -> exit 2" {
    run "$SCRIPT" --old tune --new DATA --root "$TREE"
    [ "$status" -eq 2 ]
}

@test "identical old/new -> exit 2" {
    run "$SCRIPT" --old TUNE --new TUNE --root "$TREE"
    [ "$status" -eq 2 ]
}

@test "bad --exclude id shape -> exit 2" {
    run "$SCRIPT" --old TUNE --new DATA --root "$TREE" --exclude TUNE0002
    [ "$status" -eq 2 ]
}

@test "unknown flag -> exit 2" {
    run "$SCRIPT" --old TUNE --new DATA --root "$TREE" --bogus
    [ "$status" -eq 2 ]
}

@test "--version emits version" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"rename-task-prefix.sh"* ]]
}
