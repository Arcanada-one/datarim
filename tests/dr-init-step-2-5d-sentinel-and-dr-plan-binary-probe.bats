#!/usr/bin/env bats
#
# Regression guard for two evolution-proposal stage rules:
#   1. /dr-init Step 2.5d «KB-PUSH SENTINEL AGE ADVISORY» (Class A, advisory)
#   2. /dr-plan Step 6.5 «CLI binary-name discovery probe» (Class B, contract)
#
# Both are thin markdown stage-rules; a command-file refactor that drops the
# sub-bullet silently lifts the gate. These tests assert section presence and
# the operative mechanic of each.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DR_INIT_DOC="$REPO_ROOT/commands/dr-init.md"
DR_PLAN_DOC="$REPO_ROOT/commands/dr-plan.md"

@test "dr-init.md contains Step 2.5d KB-PUSH SENTINEL AGE ADVISORY" {
    [ -f "$DR_INIT_DOC" ]
    run grep -F "2.5d. **KB-PUSH SENTINEL AGE ADVISORY**" "$DR_INIT_DOC"
    [ "$status" -eq 0 ]
}

@test "dr-init.md sentinel advisory probes datarim/.kb-last-push" {
    run grep -F "datarim/.kb-last-push" "$DR_INIT_DOC"
    [ "$status" -eq 0 ]
}

@test "dr-init.md sentinel advisory uses GNU stat -c first, BSD stat -f fallback" {
    run grep -F 'stat -c %Y datarim/.kb-last-push 2>/dev/null || stat -f %m datarim/.kb-last-push' "$DR_INIT_DOC"
    [ "$status" -eq 0 ]
}

@test "dr-init.md sentinel advisory is non-blocking" {
    # The bullet must keep its advisory framing — no failure mode.
    run grep -F "purely informational" "$DR_INIT_DOC"
    [ "$status" -eq 0 ]
}

@test "dr-plan.md Step 6.5 contains 'CLI binary-name discovery probe' bullet" {
    [ -f "$DR_PLAN_DOC" ]
    run grep -F "CLI binary-name discovery probe" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}

@test "dr-plan.md binary-name probe requires command -v after a fresh install" {
    run grep -F "command -v" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
    run grep -F "AFTER a fresh install on a sibling system" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}

@test "dr-plan.md binary-name probe offers the [to-be-discovered] marker alternative" {
    run grep -F "[to-be-discovered]" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}
