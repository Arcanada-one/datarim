#!/usr/bin/env bats
#
# Regression guard for /dr-init Step 2.5e «SYMPTOM-FRESHNESS RE-PROBE».
#
# Source: reflection-CONN-0078.md proposal #1 — CONN-0078 lost 5h29m of
# staleness because the ops-fire symptom that motivated the task was fixed
# in production between discovery and /dr-init time, but /dr-init routed the
# task straight to /dr-plan as if the symptom were still live. This step
# re-probes live state for ops-fire-shaped intake BEFORE routing onward, and
# recommends closing as superseded/stale when the probe shows the symptom
# already resolved.
#
# This is a thin markdown stage-rule; a command-file refactor that drops the
# sub-bullet silently lifts the gate. These tests assert section presence
# and the operative mechanic.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DR_INIT_DOC="$REPO_ROOT/commands/dr-init.md"

@test "dr-init.md contains Step 2.5e SYMPTOM-FRESHNESS RE-PROBE" {
    [ -f "$DR_INIT_DOC" ]
    run grep -F "2.5e. **SYMPTOM-FRESHNESS RE-PROBE**" "$DR_INIT_DOC"
    [ "$status" -eq 0 ]
}

@test "dr-init.md symptom-freshness step lists English live-fire trigger words" {
    run grep -F '"restart loop", "PROD fire", "prod fire", "active fire"' "$DR_INIT_DOC"
    [ "$status" -eq 0 ]
}

@test "dr-init.md symptom-freshness step lists Russian live-fire trigger words with allow-non-ascii marker" {
    run grep -F 'рестарт-луп' "$DR_INIT_DOC"
    [ "$status" -eq 0 ]
    run grep -F 'allow-non-ascii: russian-trigger-phrases-detected-by-the-intent-classifier' "$DR_INIT_DOC"
    [ "$status" -eq 0 ]
}

@test "dr-init.md symptom-freshness step triggers on Source:/Spawned from: ops-fire reference" {
    run grep -F '`Source:` / `Spawned from:` reference pointing at an ecosystem pre-flight/ops-fire task' "$DR_INIT_DOC"
    [ "$status" -eq 0 ]
}

@test "dr-init.md symptom-freshness step re-probes BEFORE continuing to Step 3" {
    run grep -F '**When triggered, BEFORE continuing to Step 3**' "$DR_INIT_DOC"
    [ "$status" -eq 0 ]
}

@test "dr-init.md symptom-freshness step recommends closing as superseded/stale when resolved" {
    run grep -F 'do NOT route to `/dr-plan`. Recommend closing the task as superseded/stale instead' "$DR_INIT_DOC"
    [ "$status" -eq 0 ]
}

@test "dr-init.md symptom-freshness step never blocks when symptom is still live or probe cannot run" {
    run grep -F 'this step never blocks, it only redirects an already-fixed item away from the planning pipeline' "$DR_INIT_DOC"
    [ "$status" -eq 0 ]
}

@test "dr-init.md symptom-freshness step is stack-agnostic (names no specific tool)" {
    run grep -F 'Stack-agnostic by design — this step names no specific tool' "$DR_INIT_DOC"
    [ "$status" -eq 0 ]
}

@test "dr-init.md symptom-freshness step cites reflection-CONN-0078.md as source" {
    run grep -F 'reflection-CONN-0078.md' "$DR_INIT_DOC"
    [ "$status" -eq 0 ]
}
