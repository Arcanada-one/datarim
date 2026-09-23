#!/usr/bin/env bats

@test "direct role invocation loads the canonical acceptance loop" {
  for role in planner developer reviewer tester compliance writer editor; do
    run grep -F '${DATARIM_RUNTIME:?}/skills/immutability/SKILL.md' "$BATS_TEST_DIRNAME/../agents/$role.md"
    [ "$status" -eq 0 ]
    run grep -F 'Acceptance responsibility' "$BATS_TEST_DIRNAME/../agents/$role.md"
    [ "$status" -eq 0 ]
  done
}

@test "verification roles route findings without expanding repair authority" {
  for role in tester reviewer; do
    run grep -F 'do not implement repairs unless explicitly assigned' "$BATS_TEST_DIRNAME/../agents/$role.md"
    [ "$status" -eq 0 ]
  done
}

@test "content roles retain content evidence instead of forced code tests" {
  for role in writer editor; do
    run grep -F 'content evidence' "$BATS_TEST_DIRNAME/../agents/$role.md"
    [ "$status" -eq 0 ]
  done
}
