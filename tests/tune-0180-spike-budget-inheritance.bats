#!/usr/bin/env bats
# tune-0180-spike-budget-inheritance.bats — guards the "Spike Falsifiable
# Thresholds Must Derive from the Consumer's UX Budget" subsection added to
# skills/ai-quality/SKILL.md (TUNE-0180, reflection-AGENT-0018.md Proposal 2).
#
# Source incident: AGENT-0018's Criterion 2 (<2000ms) was inherited from
# generic latency folklore rather than the actual consumer (AGENT-0017),
# whose surface tolerates 10-30s. This gate ensures the corrective rule
# stays present and stack-agnostic.

SKILL="$BATS_TEST_DIRNAME/../skills/ai-quality/SKILL.md"
GATE="$BATS_TEST_DIRNAME/../scripts/stack-agnostic-gate.sh"

@test "T1 ai-quality/SKILL.md contains the Spike Falsifiable Thresholds subsection" {
    grep -q "^## Spike Falsifiable Thresholds Must Derive from the Consumer's UX Budget$" "$SKILL"
}

@test "T2 subsection states the operator-interview-first rule for undocumented budgets" {
    grep -q "operator interview" "$SKILL"
}

@test "T3 subsection is placed before Fragment Routing (readable house order)" {
    local spike_line routing_line
    spike_line=$(grep -n "^## Spike Falsifiable Thresholds" "$SKILL" | head -1 | cut -d: -f1)
    routing_line=$(grep -n "^## Fragment Routing$" "$SKILL" | head -1 | cut -d: -f1)
    [ -n "$spike_line" ] && [ -n "$routing_line" ]
    [ "$spike_line" -lt "$routing_line" ]
}

@test "T4 stack-agnostic-gate.sh PASSes on the edited file" {
    run "$GATE" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "T5 no Cyrillic/non-ASCII introduced in the new subsection" {
    local body
    body=$(sed -n "/^## Spike Falsifiable Thresholds/,/^## Fragment Routing/p" "$SKILL")
    ! printf '%s' "$body" | grep -qP '[\x{0400}-\x{04FF}]'
}
