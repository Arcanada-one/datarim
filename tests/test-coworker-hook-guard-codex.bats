#!/usr/bin/env bats
#
# TUNE-0303: Codex CLI coworker-hook coverage parity.
#
# Spec-regression tests for `coworker-hook-guard` PreToolUse handler against
# native Codex tool names (`view`, `shell`, `apply_patch`). Each codex case
# replays the equivalent Claude-tool semantics (Read, Bash, Write).
#
# Cases A..H correspond to fixtures S1..S8 in
# datarim/tasks/TUNE-0303-fixtures.md.
#
# Tests run against the canonical Datarim source by default
# (`dev-tools/coworker-hook-guard.sh`) so they exercise the freshly-edited
# script without requiring the operator to relink ~/.local/bin first.

HOOK="${HOOK:-${BATS_TEST_DIRNAME}/../dev-tools/coworker-hook-guard.sh}"

setup() {
    [ -x "$HOOK" ] || skip "coworker-hook-guard not executable at $HOOK"
    command -v jq >/dev/null || skip "jq required"
}

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------

# Build a PreToolUse payload for a codex `view` call against $1 (path).
run_hook_view() {
    local path="$1"
    local payload
    payload=$(jq -nc --arg p "$path" '{
        hook_event_name: "PreToolUse",
        tool_name: "view",
        tool_input: { path: $p }
    }')
    printf '%s' "$payload" | "$HOOK"
}

# Build a PreToolUse payload for a codex `shell` call carrying $1 as command.
run_hook_shell() {
    local cmd="$1"
    local payload
    payload=$(jq -nc --arg c "$cmd" '{
        hook_event_name: "PreToolUse",
        tool_name: "shell",
        tool_input: { command: $c }
    }')
    printf '%s' "$payload" | "$HOOK"
}

# Codex CLI 0.133 actual emission. tool_name="exec_command" — verified via
# ~/.codex/logs_2.sqlite (DISTINCT tool names in custom_tool_call events).
run_hook_exec_command() {
    local cmd="$1"
    local payload
    payload=$(jq -nc --arg c "$cmd" '{
        hook_event_name: "PreToolUse",
        tool_name: "exec_command",
        tool_input: { command: $c }
    }')
    printf '%s' "$payload" | "$HOOK"
}

# Build a PreToolUse payload for a codex `apply_patch` call. $1 = raw patch body.
run_hook_apply_patch() {
    local patch="$1"
    local payload
    payload=$(jq -nc --arg p "$patch" '{
        hook_event_name: "PreToolUse",
        tool_name: "apply_patch",
        tool_input: { input: $p }
    }')
    printf '%s' "$payload" | "$HOOK"
}

# Materialise a 500-line tmp file for the >400-line threshold cases.
make_long_file() {
    local f
    f=$(mktemp -t cw-hook-codex-long.XXXXXX)
    seq 1 500 > "$f"
    printf '%s' "$f"
}

# ----------------------------------------------------------------------
# Cases
# ----------------------------------------------------------------------

@test "Case A — view 500-line file → deny (S2 parity with Read S1)" {
    f=$(make_long_file)
    run run_hook_view "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}

@test "Case B — view 100-line file → silent pass (below threshold)" {
    f=$(mktemp -t cw-hook-codex-short.XXXXXX)
    seq 1 100 > "$f"
    run run_hook_view "$f"
    rm -f "$f"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Case C — shell 'git diff main..HEAD' → deny (S4)" {
    run run_hook_shell "git diff main..HEAD"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}

@test "Case D — shell 'wc -l /tmp/long.txt' → silent pass (S3)" {
    run run_hook_shell "wc -l /tmp/long.txt"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Case E — shell 'git checkout -b foo' → deny (S5, TUNE-0156 HEAD-blind)" {
    run run_hook_shell "git checkout -b foo"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
    reason=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')
    case "$reason" in
        *workspace-discipline*) : ;;
        *) printf 'reason did not cite workspace-discipline: %s\n' "$reason" >&2; return 1 ;;
    esac
}

@test "Case F — apply_patch Add File prd-foo.md → deny (S6)" {
    patch=$'*** Begin Patch\n*** Add File: prd-foo.md\n+content\n*** End Patch'
    run run_hook_apply_patch "$patch"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}

@test "Case G — apply_patch Update File existing → silent pass (S7)" {
    patch=$'*** Begin Patch\n*** Update File: some-existing.py\n@@ ctx\n*** End Patch'
    run run_hook_apply_patch "$patch"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Case H — apply_patch Add archive-FOO-0001.md → silent pass (S8, exempt)" {
    patch=$'*** Begin Patch\n*** Add File: archive-FOO-0001.md\n+content\n*** End Patch'
    run run_hook_apply_patch "$patch"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# Codex CLI 0.133 native — verified through live ~/.codex/logs_2.sqlite.
# Mirrors Case C but uses the actual tool_name codex emits.

@test "Case I — exec_command 'git diff main..HEAD' → deny (live codex 0.133 emission)" {
    run run_hook_exec_command "git diff main..HEAD"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}

@test "Case J — exec_command bare 'git checkout -b foo' → deny (HEAD-blind via codex native)" {
    run run_hook_exec_command "git checkout -b foo"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}

@test "Case K — exec_command 'wc -l /tmp/long.txt' → silent pass (benign summary)" {
    run run_hook_exec_command "wc -l /tmp/long.txt"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
