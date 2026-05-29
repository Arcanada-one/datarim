#!/usr/bin/env bats
# coworker-guard-kb-backup.bats — pre-overwrite backup side-effect in the
# PreToolUse Write|Bash hook branches (TUNE-0341 Phase 4).
#
# The incident overwrote a gitignored backlog.md via an agent Bash/awk command
# and the Write tool — neither calls a framework shell library, so the only
# universal enforcement point in front of both is the PreToolUse guard hook.
# The guard backs up a critical KB file (fail-soft) BEFORE allowing the write,
# and NEVER blocks the write on backup failure. Maps to PRD V-AC-1 (hook axis)
# + plan V-9 (live smoke equivalent in-test).

HOOK="$BATS_TEST_DIRNAME/../dev-tools/coworker-hook-guard.sh"

setup() {
    command -v jq >/dev/null || skip "jq required"
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim"
    printf '# Tasks\n' > "$TMPROOT/datarim/tasks.md"
    printf 'BACKLOG ORIGINAL\nline2\n' > "$TMPROOT/datarim/backlog.md"
    command -v git >/dev/null && git -C "$TMPROOT" init -q
}

teardown() {
    rm -rf "$TMPROOT"
}

_count_baks() { find "$TMPROOT/datarim/.backups" -name "$1.*.bak" 2>/dev/null | wc -l | tr -d ' '; }

run_hook_write() {
    local f="$1" cwd="${2:-$PWD}"
    jq -nc --arg f "$f" --arg cwd "$cwd" \
        '{hook_event_name:"PreToolUse",tool_name:"Write",cwd:$cwd,tool_input:{file_path:$f}}' \
        | "$HOOK"
}

run_hook_bash() {
    local cmd="$1" cwd="${2:-$PWD}"
    jq -nc --arg c "$cmd" --arg cwd "$cwd" \
        '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$cwd,tool_input:{command:$c}}' \
        | "$HOOK"
}

# --- Write branch: backup critical KB file before overwrite -----------------

@test "W1 Write to an existing critical KB file backs it up, allows (no deny)" {
    run run_hook_write "$TMPROOT/datarim/backlog.md"
    [ "$status" -eq 0 ]
    # not a protected-docs first-draft → no deny JSON
    [ -z "$output" ] || [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // empty')" != "deny" ]
    [ "$(_count_baks backlog.md)" -eq 1 ]
}

@test "W2 the Write-branch backup holds the pre-overwrite content" {
    run_hook_write "$TMPROOT/datarim/backlog.md"
    local bak; bak="$(find "$TMPROOT/datarim/.backups" -name 'backlog.md.*.bak' | head -1)"
    [ -n "$bak" ]
    diff "$TMPROOT/datarim/backlog.md" "$bak"
}

@test "W3 Write to a NON-critical file under datarim/ does not back up" {
    printf 'x\n' > "$TMPROOT/datarim/style-guide.md"
    run run_hook_write "$TMPROOT/datarim/style-guide.md"
    [ "$status" -eq 0 ]
    [ "$(_count_baks style-guide.md)" -eq 0 ]
}

@test "W4 Write to a critical-named file OUTSIDE any KB does not back up" {
    local outside="$(mktemp -d)"
    printf 'not a kb\n' > "$outside/backlog.md"
    run run_hook_write "$outside/backlog.md"
    [ "$status" -eq 0 ]
    [ ! -d "$outside/datarim" ]
    rm -rf "$outside"
}

@test "W5 Write to a not-yet-existing critical file is a no-op (nothing to save)" {
    run run_hook_write "$TMPROOT/datarim/activeContext.md"
    [ "$status" -eq 0 ]
    [ "$(_count_baks activeContext.md)" -eq 0 ]
}

# --- Bash branch: backup before a redirect overwrite (the awk vector) -------

@test "B1 'awk ... > backlog.md' redirect backs up the critical file first" {
    run run_hook_bash "awk 'NR<1' /dev/null > $TMPROOT/datarim/backlog.md"
    [ "$status" -eq 0 ]
    [ "$(_count_baks backlog.md)" -eq 1 ]
}

@test "B2 'tee backlog.md' redirect backs up the critical file" {
    run run_hook_bash "echo x | tee $TMPROOT/datarim/backlog.md"
    [ "$status" -eq 0 ]
    [ "$(_count_baks backlog.md)" -eq 1 ]
}

@test "B3 a Bash command with no redirect to a critical file does not back up" {
    run run_hook_bash "ls -la $TMPROOT/datarim"
    [ "$status" -eq 0 ]
    [ "$(_count_baks backlog.md)" -eq 0 ]
}

@test "B4 backup side-effect never blocks the write (fail-soft on bad dir)" {
    # make .backups unwritable; the hook must still allow (no deny, exit 0)
    mkdir -p "$TMPROOT/datarim/.backups"; chmod 500 "$TMPROOT/datarim/.backups"
    run run_hook_write "$TMPROOT/datarim/backlog.md"
    chmod 700 "$TMPROOT/datarim/.backups" 2>/dev/null || true
    [ "$status" -eq 0 ]
    [ -z "$output" ] || [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // empty')" != "deny" ]
}

@test "B5 RELATIVE 'awk ... > backlog.md' from cwd inside datarim/ backs up (incident vector)" {
    # The original incident: awk ... > backlog.md run with cwd INSIDE datarim/,
    # so the redirect target is the bare relative name 'backlog.md'. The hook
    # must resolve it against the payload cwd, not skip it.
    run run_hook_bash "awk 'NR<1' /dev/null > backlog.md" "$TMPROOT/datarim"
    [ "$status" -eq 0 ]
    [ "$(_count_baks backlog.md)" -eq 1 ]
}

@test "B6 RELATIVE redirect from a NESTED cwd under the repo resolves the KB file" {
    # cwd is repo-root; target 'datarim/backlog.md' is relative to it.
    run run_hook_bash "echo x > datarim/backlog.md" "$TMPROOT"
    [ "$status" -eq 0 ]
    [ "$(_count_baks backlog.md)" -eq 1 ]
}

# --- Write branch with a relative file_path -------------------------------

@test "W6 RELATIVE Write file_path 'backlog.md' from cwd inside datarim/ backs up" {
    run run_hook_write "backlog.md" "$TMPROOT/datarim"
    [ "$status" -eq 0 ]
    [ "$(_count_baks backlog.md)" -eq 1 ]
}

# --- symlink-dir TOCTOU guard (F-dispatch-4) --------------------------------

@test "S1 a pre-existing symlinked .backups dir is refused (no write through symlink)" {
    local victim; victim="$(mktemp -d)"
    ln -s "$victim" "$TMPROOT/datarim/.backups"
    run run_hook_write "$TMPROOT/datarim/backlog.md"
    # fail-soft: never blocks the write
    [ "$status" -eq 0 ]
    # the guard must NOT have written a backup into the symlink target
    [ "$(find "$victim" -name 'backlog.md.*.bak' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
    rm -f "$TMPROOT/datarim/.backups"; rm -rf "$victim"
}
