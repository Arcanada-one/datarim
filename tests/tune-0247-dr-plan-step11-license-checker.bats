#!/usr/bin/env bats
#
# /dr-plan Step 11 Live Audit Checkpoint — license-policy checkpoint regression
# guard (TUNE-0247). `cargo audit` is advisory-only (vulnerabilities), not a
# license check; a transitive dependency (e.g. MPL-2.0 `option-ext` pulled by
# `directories`) can violate license policy without tripping the audit gate.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DR_PLAN_DOC="$REPO_ROOT/commands/dr-plan.md"

@test "T1: dr-plan.md Step 11 contains 'License-policy checkpoint' sub-bullet" {
    [ -f "$DR_PLAN_DOC" ]
    run grep -F "License-policy checkpoint" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}

@test "T2: license checkpoint names package-manager-native license checkers" {
    run grep -F "cargo deny check licenses" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
    run grep -F "pip-licenses --fail-on" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
    run grep -F "license-checker --production" "$DR_PLAN_DOC"
    [ "$status" -eq 0 ]
}

@test "T3: license checkpoint recipes are wrapped in gate:example-only markers" {
    awk '/License-policy checkpoint/{flag=1} flag && /cargo deny check licenses/{found=1} flag && /<!-- \/gate:example-only -->/{exit} END{exit !found}' "$DR_PLAN_DOC"
}

@test "T4: license checkpoint sits inside Step 11 Live Audit Checkpoint block" {
    awk '/^11\.  \*\*Live Audit Checkpoint/{flag=1} flag && /License-policy checkpoint/{found=1} flag && /^11\.5\./{exit} END{exit !found}' "$DR_PLAN_DOC"
}
