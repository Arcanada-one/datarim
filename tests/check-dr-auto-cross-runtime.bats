#!/usr/bin/env bats

# Test contract: dev-tools/check-dr-auto-cross-runtime.sh is a pure-bash smoke
# that proves the /dr-auto autonomous-mode activation contract is
# runtime-agnostic (Claude Code / Codex CLI / Cursor). See backlog TUNE-0292.
#
# Tests:
#   1. --check passes (exit 0, prints PASS) on the real repo
#   2. --report prints all three named checks as PASS
#   3. env-var independence: passes even with DATARIM_AUTO_MODE unset
#   4. --help exits 0; unknown arg exits 2
#   5. FAIL path: an empty hard_gated_actions list makes check 3 fail (exit 1)

SMOKE="$BATS_TEST_DIRNAME/../dev-tools/check-dr-auto-cross-runtime.sh"

setup() {
    [ -x "$SMOKE" ] || skip "check-dr-auto-cross-runtime.sh not executable: $SMOKE"
}

@test "1. --check passes on the real repo" {
    run bash "$SMOKE" --check
    [ "$status" -eq 0 ]
    [[ "$output" == *PASS* ]]
}

@test "2. --report names all three checks as PASS" {
    run bash "$SMOKE" --report
    [ "$status" -eq 0 ]
    [[ "$output" == *"check 1 (activation marker)"*PASS* ]]
    [[ "$output" == *"check 2 (env-var independence)"*PASS* ]]
    [[ "$output" == *"check 3 (hard-gate data)"*PASS* ]]
}

@test "3. passes with DATARIM_AUTO_MODE unset (runtime-portable)" {
    run env -u DATARIM_AUTO_MODE bash "$SMOKE" --check
    [ "$status" -eq 0 ]
}

@test "4. --help exits 0; unknown arg exits 2" {
    run bash "$SMOKE" --help
    [ "$status" -eq 0 ]
    run bash "$SMOKE" --bogus
    [ "$status" -eq 2 ]
}

@test "5. empty hard_gated_actions list fails check 3" {
    # Build an isolated dev-tools/ copy with the marker tool and a fb-rules.yaml
    # whose hard_gated_actions list is empty, so only check 3 regresses.
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/dev-tools/rules"
    cp "$BATS_TEST_DIRNAME/../dev-tools/auto-mode-marker.sh" "$tmp/dev-tools/"
    cp "$SMOKE" "$tmp/dev-tools/"
    printf 'schema_version: 1\nhard_gated_actions:\n' > "$tmp/dev-tools/rules/fb-rules.yaml"
    run bash "$tmp/dev-tools/check-dr-auto-cross-runtime.sh" --report
    [ "$status" -eq 1 ]
    [[ "$output" == *"check 3"* ]]
    rm -rf "$tmp"
}
