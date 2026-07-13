#!/usr/bin/env bats
#
# Infra-gated test skip doc + deploy-deferred PRD labelling regression guard.
#
# Stage-rule contract:
#   - skills/testing/SKILL.md MUST keep the "Infrastructure-Gated Test Skips"
#     section (probe-then-skip pattern: setup() probe, explicit-message skip,
#     "When to apply" clause distinguishing legit env-gating from masked bugs).
#   - templates/prd-template.md MUST keep the "Deploy-Phase Verification
#     Items" subsection carrying the deploy-deferred label token.
#   - commands/dr-prd.md Step 5 MUST reference the deploy-deferred labelling.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
TESTING_SKILL="$REPO_ROOT/skills/testing/SKILL.md"
PRD_TEMPLATE="$REPO_ROOT/templates/prd-template.md"
DR_PRD="$REPO_ROOT/commands/dr-prd.md"

@test "T1: testing SKILL.md contains the Infrastructure-Gated Test Skips section" {
    [ -f "$TESTING_SKILL" ]
    run grep -q "Infrastructure-Gated Test Skips" "$TESTING_SKILL"
    [ "$status" -eq 0 ]
}

@test "T2: testing skill section contains a setup() probe example" {
    run grep -F "setup() {" "$TESTING_SKILL"
    [ "$status" -eq 0 ]
    run grep -F "redis-cli -h" "$TESTING_SKILL"
    [ "$status" -eq 0 ]
}

@test "T3: testing skill section requires an explicit-message skip" {
    run grep -F 'skip "no live Redis at' "$TESTING_SKILL"
    [ "$status" -eq 0 ]
}

@test "T4: testing skill section carries a When to apply clause for the infra-gate pattern" {
    run grep -F "**When to apply.** Any test whose assertions require a live broker" "$TESTING_SKILL"
    [ "$status" -eq 0 ]
}

@test "T5: prd-template.md carries a Deploy-Phase Verification heading" {
    [ -f "$PRD_TEMPLATE" ]
    run grep -q "Deploy-Phase Verification Items" "$PRD_TEMPLATE"
    [ "$status" -eq 0 ]
}

@test "T6: prd-template.md deploy-deferred token appears under the Deploy-Phase heading" {
    run grep -qi "deploy-deferred" "$PRD_TEMPLATE"
    [ "$status" -eq 0 ]
    # confirm the token appears within a few lines of the heading, not elsewhere
    run awk '/Deploy-Phase Verification Items/,/^## /' "$PRD_TEMPLATE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "deploy-deferred"
}

@test "T7: dr-prd.md Step 5 references the deploy-deferred labelling" {
    [ -f "$DR_PRD" ]
    run grep -qi "deploy-deferred" "$DR_PRD"
    [ "$status" -eq 0 ]
}
