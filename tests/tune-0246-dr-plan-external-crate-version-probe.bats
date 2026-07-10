#!/usr/bin/env bats
#
# /dr-plan Step 6 Technology Validation — external-crate version probe
# regression guard (TUNE-0246). When a plan introduces a NEW external
# library dependency, the planner must query the package registry for the
# latest stable version and record version + rationale, rather than guessing
# or copying a pin from memory (ARAS-0004).

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DR_PLAN_DOC="$REPO_ROOT/commands/dr-plan.md"

@test "T1: dr-plan.md Step 6 contains 'External-crate version probe' sub-bullet" {
    [ -f "$DR_PLAN_DOC" ]
    run grep -F "External-crate version probe" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}

@test "T2: probe trigger is scoped to a NEW dependency not already in the workspace manifest" {
    run grep -F "NEW external library dependency not already present in the workspace manifest" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}

@test "T3: probe requires recording chosen version + rationale in Component Breakdown" {
    run grep -F "record the chosen version + a one-sentence rationale in the plan's Component Breakdown" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}

@test "T4: probe names package-manager-native registry lookups across ecosystems" {
    run grep -F "cargo search <crate>" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
    run grep -F "pnpm view <pkg> versions" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
    run grep -F "pip index versions <pkg>" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}

@test "T5: probe bullet sits inside Step 6 Technology Validation, before Step 6.5" {
    awk '/^6\.  \*\*Technology Validation\*\*/{flag=1} flag && /External-crate version probe/{found=1} flag && /^6\.5\./{exit} END{exit !found}' "$DR_PLAN_DOC"
}

@test "T6: registry-lookup recipes are wrapped in gate:example-only markers" {
    awk '/External-crate version probe/{flag=1} flag && /cargo search <crate>/{found=1} flag && /<!-- \/gate:example-only -->/{exit} END{exit !found}' "$DR_PLAN_DOC"
}
