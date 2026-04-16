#!/usr/bin/env bats
#
# T2 (TUNE-0013): spec-regression tests for skills/reflecting.md.
#
# Contract under test (v1.10.0 pipeline):
#   AC-3 / AC-4: the reflection workflow must exist as a skill (not as a
#   standalone command) and must declare itself internal-only (invoked by
#   /dr-archive Step 0.5).
#
#   Content parity with the retired /dr-reflect command (sections 3-7) is
#   required so reflection behavior is preserved across the refactor.

SKILL="${BATS_TEST_DIRNAME}/../skills/reflecting.md"

@test "skill file exists" {
    [ -f "$SKILL" ]
}

@test "frontmatter declares name: reflecting" {
    run grep -E "^name: reflecting" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "frontmatter description mentions internal invocation by /dr-archive" {
    run grep -iE "^description:.*/dr-archive|internal.*archive|Step 0.5" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "skill references Class A evolution-proposal gate" {
    run grep -F "Class A" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "skill references Class B evolution-proposal gate" {
    run grep -F "Class B" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "skill references evolution.md (Class A/B contract source of truth)" {
    run grep -F "evolution.md" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "skill mentions reflection document output path" {
    run grep -F "datarim/reflection/" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "skill mentions evolution-log path" {
    run grep -F "evolution-log.md" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "skill describes health-metrics check step" {
    run grep -iE "health.metrics|health check|Health Check" "$SKILL"
    [ "$status" -eq 0 ]
}

@test "skill describes follow-up-task detection step" {
    run grep -iE "follow.up|Next Steps|follow-up task" "$SKILL"
    [ "$status" -eq 0 ]
}
