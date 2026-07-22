#!/usr/bin/env bats

# Test contract: dev-tools/check-dr-auto-cross-runtime.sh is a pure-bash smoke
# that proves the /dr-auto autonomous-mode activation contract is
# runtime-agnostic (Claude Code / Codex CLI / Cursor). See backlog TUNE-0292.
#
# The three properties it asserts mirror what an operator dogfooding /dr-auto on
# a non-Claude runtime must confirm:
#   1. activation marker  — reassert writes a parseable per-task marker
#   2. env-var independence — subagent-active decides active/non-auto with
#                             DATARIM_AUTO_MODE unset (a spawned Codex/Cursor
#                             subagent does not inherit the shell env var)
#   3. hard-gate data     — fb-rules.yaml declares a non-empty
#                           hard_gated_actions list (never auto-executed)
#
# Tests:
#   1. --check passes (exit 0, prints PASS) on the real repo
#   2. --report prints all three named checks as PASS
#   3. env-var independence: passes even with DATARIM_AUTO_MODE unset
#   4. --help exits 0; unknown arg exits 2
#   5. FAIL path: an empty hard_gated_actions list makes check 3 fail (exit 1)
#   6. missing marker tool → precondition error (exit 2)

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
    # Build an isolated dev-tools/ copy with the marker tool + an empty
    # fb-rules.yaml so ONLY check 3 regresses (checks 1/2 still use the real
    # marker tool copied alongside).
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

@test "6. missing marker tool is a precondition error (exit 2)" {
    # Copy only the smoke + rules (no auto-mode-marker.sh) → precondition fails.
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/dev-tools/rules"
    cp "$SMOKE" "$tmp/dev-tools/"
    printf 'hard_gated_actions:\n  - prod_deploy\n' > "$tmp/dev-tools/rules/fb-rules.yaml"
    run bash "$tmp/dev-tools/check-dr-auto-cross-runtime.sh" --check
    [ "$status" -eq 2 ]
    [[ "$output" == *"auto-mode-marker.sh"* ]]
    rm -rf "$tmp"
}
