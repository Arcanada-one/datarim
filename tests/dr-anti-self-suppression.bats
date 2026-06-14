#!/usr/bin/env bats
# Tests for the anti-self-suppression rule (Vector B): a reflection lesson that
# recurs (matches a prior reflection OR describes a recurrence) MUST NOT be
# declined as "redundant with existing contract" — it MUST be promoted via the
# evolution category `promote-recurring-incident-to-gate`.
#
# These are contract-presence tests over the shipped instruction surface: they
# assert the rule and category exist and are wired into the three call-sites
# (evolution/SKILL.md, evolution/class-ab-gate.md, reflecting/SKILL.md).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    EVO="$REPO_ROOT/skills/evolution/SKILL.md"
    GATE="$REPO_ROOT/skills/evolution/class-ab-gate.md"
    REFLECT="$REPO_ROOT/skills/reflecting/SKILL.md"
}

@test "new evolution category promote-recurring-incident-to-gate exists in evolution/SKILL.md" {
    grep -q 'promote-recurring-incident-to-gate' "$EVO"
}

@test "anti-self-suppression rule present in class-ab-gate.md" {
    grep -qi 'self-suppress' "$GATE"
    grep -qi 'recurr' "$GATE"
}

@test "class-ab-gate forbids 'redundant with existing contract' decline on recurrence" {
    # the forbidden-decline phrase MUST be cited so the rule is unambiguous
    grep -qi 'redundant' "$GATE"
}

@test "reflecting Step 6 instructs a recurrence check before declining a proposal" {
    grep -qi 'recurr' "$REFLECT"
    # must reference grepping prior reflections (the deterministic first pass)
    grep -Eqi 'prior reflection|reflection/\*\.md|incident.class' "$REFLECT"
}

@test "reflecting cites the new category as the promotion destination" {
    grep -q 'promote-recurring-incident-to-gate' "$REFLECT"
}

@test "recurrence rule is false-positive-bounded (fires only on demonstrated recurrence)" {
    # a novel lesson can still be declined — the rule must say so explicitly
    grep -Eqi 'only.*recurr|novel.*declin|recurrence.*demonstrat|demonstrated recurrence' "$GATE"
}
