#!/usr/bin/env bats
#
# TUNE-0156: Multi-agent workspace HEAD-blind branch creation gate.
#
# Spec-regression tests for the PreToolUse hook coworker-hook-guard. The new
# Bash-case detector denies `git checkout -b NAME` / `git switch -c NAME`
# without an explicit start-point (4th positional word). Explicit `main`,
# SHA, or `HEAD` after the branch name short-circuits the deny.
#
# Cases follow PRD-TUNE-0156 § Success Criteria (AC-2..AC-7).
# Fixtures: datarim/tasks/TUNE-0156-fixtures.md.

HOOK="${HOOK:-$HOME/.local/bin/coworker-hook-guard}"

setup() {
    [ -x "$HOOK" ] || skip "coworker-hook-guard not executable at $HOOK"
    command -v jq >/dev/null || skip "jq required"
}

# Helper: invoke hook with a PreToolUse Bash payload carrying $1 as command.
run_hook_bash() {
    local cmd="$1"
    local payload
    payload=$(jq -nc --arg c "$cmd" '{
        hook_event_name: "PreToolUse",
        tool_name: "Bash",
        tool_input: { command: $c }
    }')
    printf '%s' "$payload" | "$HOOK"
}

@test "Case A — bare 'git checkout -b foo' → deny (AC-2)" {
    run run_hook_bash "git checkout -b foo"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}

@test "Case B — 'git checkout -b foo main' → silent pass (AC-3)" {
    run run_hook_bash "git checkout -b foo main"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Case C — 'git checkout -b foo HEAD' → silent pass (AC-4)" {
    run run_hook_bash "git checkout -b foo HEAD"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Case D — bare 'git switch -c bar' → deny (AC-5 deny axis)" {
    run run_hook_bash "git switch -c bar"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}

@test "Case D2 — 'git switch -c bar main' → silent pass (AC-5 allow axis)" {
    run run_hook_bash "git switch -c bar main"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "Case F — deny reason cites workspace-discipline mandate (AC-6)" {
    run run_hook_bash "git checkout -b foo"
    [ "$status" -eq 0 ]
    reason=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')
    case "$reason" in
        *workspace-discipline*) : ;;
        *) printf 'reason did not cite workspace-discipline: %s\n' "$reason" >&2; return 1 ;;
    esac
}

@test "Case E — pre-existing trigger 'git log -p' still denies (no regression)" {
    run run_hook_bash "git log -p"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}
