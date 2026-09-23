#!/usr/bin/env bats

@test "direct role invocation loads the canonical acceptance loop" {
  for role in planner developer reviewer tester compliance writer editor; do
    run grep -F '${DATARIM_RUNTIME:?}/skills/immutability/SKILL.md' "$BATS_TEST_DIRNAME/../agents/$role.md"
    [ "$status" -eq 0 ]
    run grep -F 'Acceptance responsibility' "$BATS_TEST_DIRNAME/../agents/$role.md"
    [ "$status" -eq 0 ]
  done
}

@test "canonical loop loads applicable customer delivery before prework and delegation" {
  local repo="${BATS_TEST_DIRNAME}/.." prework
  # Inspect the common entry before baseline creation, not an unrelated footer.
  # This checks instruction reachability, not actual model compliance.
  prework="$(sed -n '/^#### Acceptance and Evidence Loop$/,/^Store the complete task contract/p' "$repo/skills/immutability/SKILL.md")"
  [[ "$prework" == *'For customer-derived delivery requirements, MUST LOAD'* ]]
  [[ "$prework" == *'${DATARIM_RUNTIME:?}/skills/customer-delivery/SKILL.md'* ]]
  [[ "$prework" == *'before establishing the pre-work baseline or delegating affected work'* ]]
  [[ "$prework" == *'U3 pre-work selection and inherited-context rules'* ]]
  [[ "$prework" == *'does not expand task scope or grant production approval'* ]]
  [ -f "$repo/skills/customer-delivery/SKILL.md" ]
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
