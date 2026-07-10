#!/usr/bin/env bats
#
# /dr-plan Step 6.6 "Auth-Parameter Widening Axis Enumeration" regression guard.
#
# Stage-rule contract: commands/dr-plan.md MUST keep the axis-enumeration
# sub-step for auth-parameter-widening plans — it requires every JWT claim
# the widened code touches to be enumerated and independently spec-covered
# on both accept and reject paths, preventing a plan from passing on the
# strength of the one axis it changed while an orthogonal axis ships a hole.
#
# Three cases cover the three operative signals — section presence, the
# enumerated claim set, and the per-axis spec-case requirement.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DR_PLAN_DOC="$REPO_ROOT/commands/dr-plan.md"

@test "T1: dr-plan.md contains the Auth-Parameter Widening Axis Enumeration step" {
    [ -f "$DR_PLAN_DOC" ]
    run grep -F "Auth-Parameter Widening Axis Enumeration" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}

@test "T2: axis enumeration step names all five JWT claims" {
    run grep -F '`iss`, `aud`, `scope`, `alg`, `exp`' "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}

@test "T3: axis enumeration step requires one spec case per axis variant, both paths" {
    run grep -F "one dedicated spec case per axis variant" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
    run grep -F "accept path and the reject path" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}
