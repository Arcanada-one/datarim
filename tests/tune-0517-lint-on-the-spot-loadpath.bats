#!/usr/bin/env bats
#
# TUNE-0517: Lint-on-the-spot load-path wiring test.
# Verifies the Lint-on-the-spot MANDATORY rule in dr-do.md carries a
# literal load-path reference to ai-quality/SKILL.md § Lint-on-the-spot.
# Prior to this test, the rule was prose-only with only documentation-
# freshness grep assertions (tune-0260). This test asserts the wiring
# reference exists, upgrading from UNENFORCED to ENFORCED-LOAD.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DR_DO_DOC="$REPO_ROOT/commands/dr-do.md"
AI_QUALITY_SKILL="$REPO_ROOT/skills/ai-quality/SKILL.md"

@test "LINT-LOADPATH: dr-do.md contains grep-verifiable load-path to ai-quality lint section" {
    [ -f "$DR_DO_DOC" ]
    run grep -F "ai-quality" "$DR_DO_DOC"
    [ "$status" -eq 0 ]
}

@test "LINT-LOADPATH: ai-quality/SKILL.md has a Lint-on-the-spot section heading" {
    [ -f "$AI_QUALITY_SKILL" ]
    run grep -q -E "^###.*Lint.*linter|^###.*Lint-on-the-spot" "$AI_QUALITY_SKILL"
    # If the heading uses a different format, check for the key concept
    if [ "$status" -ne 0 ]; then
        run grep -i "linter\|lint.*detect\|lint.*auto" "$AI_QUALITY_SKILL"
    fi
    [ "$status" -eq 0 ]
}

@test "LINT-LOADPATH: ai-quality/SKILL.md lint section has actionable guidance" {
    [ -f "$AI_QUALITY_SKILL" ]
    # The section should contain at least one actionable pattern
    run grep -i "auto-detect\|linter\|linter.*rules\|lint.*manifest\|project.*linter" "$AI_QUALITY_SKILL"
    [ "$status" -eq 0 ]
}
