#!/usr/bin/env bats
# TUNE-0338 — Datarim framework runtime apply for AGENT-0017 reflection
# Class A proposals A1/A2/A3 (stack-agnostic).
#
# A1 = Session-scoped Deferred-Items table in dr-qa.md QA report template.
# A2 = Pre-/dr-do coworker plan-extract recommendation in dr-do.md
#      (trigger: plan >400 lines + session covers >=2 phases).
# A3 = Plan <-> Creative deploy-dependency cross-reference rule in dr-plan.md
#      + dr-design.md (annotation `[deploy-gated — see creative-{ID}.md §
#      Decision]`).

DR_QA="$BATS_TEST_DIRNAME/../commands/dr-qa.md"
DR_DO="$BATS_TEST_DIRNAME/../commands/dr-do.md"
DR_PLAN="$BATS_TEST_DIRNAME/../commands/dr-plan.md"
DR_DESIGN="$BATS_TEST_DIRNAME/../commands/dr-design.md"

# ---------------------------------------------------------------------------
# A1 — dr-qa.md Deferred-Items table
# ---------------------------------------------------------------------------

@test "A1: dr-qa.md QA report template has a Deferred Items section" {
    run grep -ci 'Deferred Items' "$DR_QA"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "A1: Deferred Items section is explicitly session-scoped" {
    run grep -i 'session-scoped' "$DR_QA"
    [ "$status" -eq 0 ]
}

@test "A1: Deferred Items section documents carry-forward to backlog.md" {
    run grep -i 'backlog.md' "$DR_QA"
    [ "$status" -eq 0 ]
}

@test "A1: OUTPUT step wires the Deferred Items table into the report" {
    run grep -A2 '\*\*OUTPUT\*\*: Write .datarim/qa/qa-report' "$DR_QA"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Deferred Items"* ]]
}

# ---------------------------------------------------------------------------
# A2 — dr-do.md coworker plan-extract recommendation
# ---------------------------------------------------------------------------

@test "A2: dr-do.md recommends a coworker plan-extract pass" {
    run grep -ci 'plan-extract' "$DR_DO"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "A2: plan-extract recommendation cites coworker" {
    run grep -i 'plan-extract' "$DR_DO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"coworker"* ]]
}

@test "A2: plan-extract recommendation is trigger-gated on plan length (400 lines)" {
    run grep -i 'plan-extract' "$DR_DO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"400"* ]]
}

@test "A2: plan-extract recommendation is trigger-gated on multi-phase sessions" {
    run grep -i 'plan-extract' "$DR_DO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"phase"* ]] || [[ "$output" == *"Phase"* ]]
}

@test "A2: plan-extract recommendation is advisory, not mandatory" {
    run grep -B2 -A2 -i 'plan-extract' "$DR_DO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"advisory"* ]] || [[ "$output" == *"recommend"* ]]
}

# ---------------------------------------------------------------------------
# A3 — dr-plan.md / dr-design.md deploy-dependency cross-reference
# ---------------------------------------------------------------------------

@test "A3: dr-plan.md defines the deploy-gated annotation contract" {
    run grep -ci 'deploy-gated' "$DR_PLAN"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "A3: dr-plan.md annotation cites the exact bracket token" {
    run grep -c '\[deploy-gated — see creative-{TASK-ID}.md § Decision\]' "$DR_PLAN"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "A3: dr-plan.md cross-reference rule names the creative doc + Decision section" {
    run grep -i 'deploy-gated' "$DR_PLAN"
    [ "$status" -eq 0 ]
    [[ "$output" == *"creative"* ]]
}

@test "A3: dr-design.md instructs marking a Decision as deploy-gated" {
    run grep -ci 'deploy-gated' "$DR_DESIGN"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
