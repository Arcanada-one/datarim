#!/usr/bin/env bats
#
# Anti-decay spec-regression: skills/autonomous-mode/SKILL.md must mandate
# an independent, clean-context compliance agent for autonomous runs on
# framework self-modification tasks (self-reflexive-bias mitigation).

SKILL="${BATS_TEST_DIRNAME}/../skills/autonomous-mode/SKILL.md"

@test "skill file exists" {
    [ -f "$SKILL" ]
}

@test "Independent Compliance section header present" {
    run grep -cE "^## Independent Compliance on Framework Self-Modification" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "section mandates a clean context with no do/qa session history" {
    run grep -ciE "clean context" "$SKILL"
    [ "$status" -eq 0 ]
    run grep -ciE "no do/qa session history" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "section names the self-reflexive bias rationale" {
    run grep -ciE "self-reflexive bias" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "section uses MUST (mandatory, not advisory) for self-modification tasks" {
    sec_line=$(grep -nE "^## Independent Compliance on Framework Self-Modification" "$SKILL" | head -1 | cut -d: -f1)
    [ -n "$sec_line" ]
    next_h2=$(awk -v start="$sec_line" 'NR>start && /^## / {print NR; exit}' "$SKILL")
    [ -n "$next_h2" ] || next_h2=$(wc -l < "$SKILL")
    body=$(sed -n "${sec_line},${next_h2}p" "$SKILL")
    count=$(printf '%s\n' "$body" | grep -cE "MUST" || true)
    [ "$count" -ge 1 ]
}
