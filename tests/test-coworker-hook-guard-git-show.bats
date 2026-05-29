#!/usr/bin/env bats
#
# git-show blob-read disambiguation for coworker-hook-guard (Bash branch).
#
# `git show <commit>` is a diff/log dump — large, delegation-worthy → deny.
# `git show <ref>:<path>` is a blob read (cat of a file at a revision) — small,
# structured, signal not bulk → passthrough. The reset-case also covers output
# limiters (| sed, | awk, --no-pager, stdout redirect) that make the output
# short or empty (so the "pipe into coworker ask" suggestion is nonsensical).
#
# Tests run against the canonical Datarim source by default.

HOOK="${HOOK:-${BATS_TEST_DIRNAME}/../dev-tools/coworker-hook-guard.sh}"

setup() {
    [ -x "$HOOK" ] || skip "coworker-hook-guard not executable at $HOOK"
    command -v jq >/dev/null || skip "jq required"
}

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

decision_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision'; }

# ----------------------------------------------------------------------
# Blob read (<ref>:<path>) → passthrough
# ----------------------------------------------------------------------

@test "git show HEAD:README.md → silent pass (blob read, colon shape)" {
    run run_hook_bash "git show HEAD:README.md"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "git show HEAD:README.md | sed -n '1,20p' → silent pass (blob + sed reset)" {
    run run_hook_bash "git show HEAD:README.md | sed -n '1,20p'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "git show abc1234:src/app.py → silent pass (blob read at SHA)" {
    run run_hook_bash "git show abc1234:src/app.py"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ----------------------------------------------------------------------
# Diff/log dump (bare commit) → deny
# ----------------------------------------------------------------------

@test "git show abc1234 → deny (diff, no colon → delegation-worthy)" {
    run run_hook_bash "git show abc1234"
    [ "$status" -eq 0 ]
    [ "$(decision_of "$output")" = "deny" ]
}

@test "git show HEAD~3 → deny (diff, no colon)" {
    run run_hook_bash "git show HEAD~3"
    [ "$status" -eq 0 ]
    [ "$(decision_of "$output")" = "deny" ]
}

# ----------------------------------------------------------------------
# Extended reset-case (output limiters on a diff dump) → passthrough
# ----------------------------------------------------------------------

@test "git show abc1234 | awk '{print}' → silent pass (| awk reset)" {
    run run_hook_bash "git show abc1234 | awk '{print \$1}'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "git show abc1234 | sed -n '1,5p' → silent pass (| sed reset)" {
    run run_hook_bash "git show abc1234 | sed -n '1,5p'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "git --no-pager show abc1234 → silent pass (--no-pager reset)" {
    run run_hook_bash "git --no-pager show abc1234"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "git show abc1234 > /tmp/out.diff → silent pass (redirect reset, no stdout)" {
    run run_hook_bash "git show abc1234 > /tmp/out.diff"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ----------------------------------------------------------------------
# Regression — pre-existing triggers unaffected
# ----------------------------------------------------------------------

@test "git diff main..HEAD still denies (no regression)" {
    run run_hook_bash "git diff main..HEAD"
    [ "$status" -eq 0 ]
    [ "$(decision_of "$output")" = "deny" ]
}

@test "git log -p still denies (no regression)" {
    run run_hook_bash "git log -p"
    [ "$status" -eq 0 ]
    [ "$(decision_of "$output")" = "deny" ]
}
