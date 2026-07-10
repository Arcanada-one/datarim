#!/usr/bin/env bats
# tune-0179-probe-before-harness.bats — TUNE-0179: markdown-smoke guard that
# the "Probe Before Harness" rule exists in skills/ai-quality/SKILL.md.
#
# Source: reflection-AGENT-0018.md Proposal 1 (Class A). A 30-second probe
# against the real external CLI disproved a docs-based "persistent stdin
# pipe" assumption, saving ~200 lines of wrapper code and a day of
# false-build work. This test is intentionally light (markdown-smoke per
# the backlog item) — it asserts section presence and gate cleanliness, not
# prose content.

SKILL="$BATS_TEST_DIRNAME/../skills/ai-quality/SKILL.md"
GATE="$BATS_TEST_DIRNAME/../scripts/stack-agnostic-gate.sh"

@test "T1 skills/ai-quality/SKILL.md contains a Probe Before Harness section" {
    [ -f "$SKILL" ]
    grep -q '^## Probe Before Harness$' "$SKILL"
}

@test "T2 Probe Before Harness section precedes Fragment Routing" {
    local probe fragment
    probe=$(grep -n '^## Probe Before Harness$' "$SKILL" | cut -d: -f1)
    fragment=$(grep -n '^## Fragment Routing$' "$SKILL" | cut -d: -f1)
    [ -n "$probe" ] && [ -n "$fragment" ]
    [ "$probe" -lt "$fragment" ]
}

@test "T3 stack-agnostic-gate.sh passes on skills/ai-quality/SKILL.md" {
    [ -x "$GATE" ]
    run "$GATE" "$SKILL"
    [ "$status" -eq 0 ]
}
