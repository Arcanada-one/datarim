#!/usr/bin/env bats
#
# /dr-plan Step 6.5 «External target reality-probe» regression guard
# (absorbed TUNE-0276 → TUNE-0279 Phase A V-AC-A7).
#
# Stage-rule contract: commands/dr-plan.md MUST keep the External target
# reality-probe sub-bullet inside Step 6.5 — it forbids locking memory-cited
# filesystem paths or URLs into a plan without `ls`/`curl` verification.
# Accidental removal during command refactors silently lifts the gate.
#
# Three cases cover the three operative signals — section presence, probe
# mechanic (ls + curl), and failure signal (HTTP 000 / DNS unresolved).

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DR_PLAN_DOC="$REPO_ROOT/commands/dr-plan.md"

@test "T1: dr-plan.md contains 'External target reality-probe' sub-bullet" {
    [ -f "$DR_PLAN_DOC" ]
    run grep -F "External target reality-probe" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}

@test "T2: dr-plan.md probe mechanic cites both 'ls' and 'curl' invocations" {
    run grep -F 'ls "<path>"' "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
    run grep -F "curl -fsSL -o /dev/null -w '%{http_code}\\n'" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}

@test "T3: dr-plan.md flags HTTP 000 (DNS unresolved) as failure signal" {
    run grep -F "HTTP \`000\` (DNS does not resolve)" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}
