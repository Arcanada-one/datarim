#!/usr/bin/env bats
# tune-0181-spike-defer-protocol.bats — guards the "Spike-Defer-to-Production
# Protocol" subsection added to skills/ai-quality/SKILL.md (TUNE-0181,
# reflection-AGENT-0018.md Proposal 3).
#
# Source incident: Class B HELD proposal asking to rewrite spike contract
# semantics — a spike proves feasibility in isolation; its output is a
# decision + a follow-up task, never directly-shipped code. This gate
# ensures the corrective rule stays present and stack-agnostic.

SKILL="$BATS_TEST_DIRNAME/../skills/ai-quality/SKILL.md"
GATE="$BATS_TEST_DIRNAME/../scripts/stack-agnostic-gate.sh"

@test "T1 ai-quality/SKILL.md contains the Spike-Defer-to-Production Protocol subsection" {
    grep -q "^## Spike-Defer-to-Production Protocol$" "$SKILL"
}

@test "T2 subsection states spike output is a decision plus follow-up task, not shipped code" {
    grep -q "go/no-go decision" "$SKILL"
    grep -q "follow-up production task" "$SKILL"
}

@test "T3 subsection states spike code does not auto-promote to production" {
    grep -q "does NOT auto-promote" "$SKILL"
}

@test "T4 subsection is placed after Spike Falsifiable Thresholds and before Fragment Routing (readable house order)" {
    local thresholds_line defer_line routing_line
    thresholds_line=$(grep -n "^## Spike Falsifiable Thresholds" "$SKILL" | head -1 | cut -d: -f1)
    defer_line=$(grep -n "^## Spike-Defer-to-Production Protocol$" "$SKILL" | head -1 | cut -d: -f1)
    routing_line=$(grep -n "^## Fragment Routing$" "$SKILL" | head -1 | cut -d: -f1)
    [ -n "$thresholds_line" ] && [ -n "$defer_line" ] && [ -n "$routing_line" ]
    [ "$thresholds_line" -lt "$defer_line" ]
    [ "$defer_line" -lt "$routing_line" ]
}

@test "T5 stack-agnostic-gate.sh PASSes on the edited file" {
    run "$GATE" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "T6 no Cyrillic/non-ASCII introduced in the new subsection" {
    local body
    body=$(sed -n "/^## Spike-Defer-to-Production Protocol/,/^## Fragment Routing/p" "$SKILL")
    ! printf '%s' "$body" | grep -qP '[\x{0400}-\x{04FF}]'
}

@test "T7 no bare real task-ID provenance embedded in the subsection body" {
    local body
    body=$(sed -n "/^## Spike-Defer-to-Production Protocol/,/^## Fragment Routing/p" "$SKILL")
    ! printf '%s' "$body" | grep -qE 'AGENT-0018|TUNE-0181'
}
