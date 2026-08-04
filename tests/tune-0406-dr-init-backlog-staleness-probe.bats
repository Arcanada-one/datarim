#!/usr/bin/env bats
#
# /dr-init Step 3.6 "Backlog-entry staleness probe" regression guard.
#
# Stage-rule contract: commands/dr-init.md MUST keep the advisory staleness
# probe for aged high-priority backlog picks — when the picked entry is P1/P2,
# older than ~14 days, and names concrete files/mechanisms, the named paths
# are live-probed BEFORE the brief is accepted as fact and a staleness
# advisory is printed. Sibling of the ops-fire symptom-freshness re-probe
# (Step 2.5e) — the two steps split the live-symptom class vs the general
# aged-entry class and must not collapse into one.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DR_INIT="$REPO_ROOT/commands/dr-init.md"

# Extract the Step 3.6 block: from its heading to the next top-level step.
step_block() {
    awk '/^3\.6\. \*\*BACKLOG-ENTRY STALENESS PROBE\*\*/ {flag=1; print; next}
         flag && /^[0-9]+\./ {exit}
         flag {print}' "$DR_INIT"
}

@test "S1: dr-init.md contains the BACKLOG-ENTRY STALENESS PROBE step" {
    [ -f "$DR_INIT" ]
    run grep -c 'BACKLOG-ENTRY STALENESS PROBE' "$DR_INIT"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "S2: probe triggers on P1/P2 priority AND ~14-day age AND concrete file/mechanism claims" {
    local block; block=$(step_block)
    [ -n "$block" ]
    [[ "$block" == *'`P1` or `P2`'* ]]
    [[ "$block" == *"14 days"* ]]
    [[ "$block" == *"names concrete files"* ]]
}

@test "S3: probe runs BEFORE the brief is accepted as fact and prints a staleness advisory" {
    local block; block=$(step_block)
    [ -n "$block" ]
    [[ "$block" == *"BEFORE accepting the brief as fact"* ]]
    [[ "$block" == *"STALENESS ADVISORY"* ]]
}

@test "S4: probe is advisory/non-blocking and does not duplicate the 2.5e ops-fire re-probe" {
    local block; block=$(step_block)
    [ -n "$block" ]
    [[ "$block" == *"advisory, non-blocking"* ]]
    [[ "$block" == *"this step never blocks"* ]]
    [[ "$block" == *"Step 2.5e"* ]]
    [[ "$block" == *"do NOT duplicate that probe here"* ]]
}

@test "S5: fully-superseded disposition recommends closing instead of initialising" {
    local block; block=$(step_block)
    [ -n "$block" ]
    [[ "$block" == *"superseded/stale instead of initialising"* ]]
}

@test "S6: dr-init.md passes the history-agnostic task-ID gate after the addition" {
    run bash "$REPO_ROOT/scripts/task-id-gate.sh" "$DR_INIT"
    [ "$status" -eq 0 ]
}

@test "S7: dr-init.md passes the stack-agnostic gate after the addition" {
    run bash "$REPO_ROOT/scripts/stack-agnostic-gate.sh" "$DR_INIT"
    [ "$status" -eq 0 ]
}
