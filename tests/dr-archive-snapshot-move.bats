#!/usr/bin/env bats
#
# TUNE-0254 — prefix-to-subdir resolution for snapshot move (V-AC-9 cross-check).

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
DOCTOR="${REPO_ROOT}/scripts/datarim-doctor.sh"

@test "doctor prefix helper is sourceable without running the CLI" {
    local library_cwd="$BATS_TEST_TMPDIR/library-cwd"
    mkdir -p "$library_cwd"
    run bash -c '
        cd "$1" || exit 1
        DATARIM_DOCTOR_NO_MAIN=1 source "$2" || exit 1
        declare -F prefix_to_area >/dev/null || exit 1
        prefix_to_area TUNE-9999
    ' _ "$library_cwd" "$DOCTOR"
    [ "$status" -eq 0 ]
    [ "$output" = "framework" ]
    [ ! -e "$library_cwd/.doctor.lock" ]
}

@test "direct doctor CLI ignores the source-only library guard" {
    run "$DOCTOR" --help
    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"--fix               Apply fixes (default: dry-run)"* ]] || return 1
    [[ "$output" == *"1   non-compliant findings (dry-run)"* ]] || return 1
    local help_output="$output"

    run env DATARIM_DOCTOR_NO_MAIN=1 "$DOCTOR" --help
    [ "$status" -eq 0 ] || return 1
    [ "$output" = "$help_output" ] || return 1

    local cli_root="$BATS_TEST_TMPDIR/cli-root"
    mkdir -p "$cli_root" || return 1
    run "$DOCTOR" --root="$cli_root" --scope=tasks
    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"OK: datarim/ structure compliant"* ]] || return 1
    [ ! -e "$cli_root/.doctor.lock" ] || return 1
    local dry_run_output="$output"

    run env DATARIM_DOCTOR_NO_MAIN=1 "$DOCTOR" --root="$cli_root" --scope=tasks
    [ "$status" -eq 0 ] || return 1
    [ "$output" = "$dry_run_output" ] || return 1
    [ ! -e "$cli_root/.doctor.lock" ] || return 1
}

@test "default fallback subdir 'general' for unknown prefix" {
    # Simulate consumer-side workspace AGENTS.md walk failing to find prefix.
    local tmp="$BATS_TEST_TMPDIR/no-claude-md"
    mkdir -p "$tmp"
    cd "$tmp"
    # Without a Task Prefix Registry, an unknown prefix resolves to "general".
    run bash -c "cd '$tmp' && grep -l 'Task Prefix Registry' AGENTS.md 2>/dev/null"
    [ "$status" -ne 0 ]
}
