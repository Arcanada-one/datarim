#!/usr/bin/env bats
# TUNE-0409 — Step 6.5 V-AC post-implementation authoring order contract regression guard.
# Prevents F1-class probes (audit-schema / command-output-shape V-AC drafted
# blind from spec, checking a field absent from the real output) by requiring
# the probe be authored or re-verified AFTER a live run.

DR_PLAN="$BATS_TEST_DIRNAME/../commands/dr-plan.md"

bullet_block() {
    awk 'tolower($0) ~ /v-ac post-implementation authoring order/ {flag=1; print; next}
         flag && /^    -   \*\*/ {exit}
         flag {print}' "$DR_PLAN"
}

@test "Step 6.5 contains 'V-AC post-implementation authoring order' bullet" {
    run grep -ci 'V-AC post-implementation authoring order' "$DR_PLAN"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "probe bullet is MANDATORY and scoped to audit-schema / command-output-shape V-AC" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"MANDATORY"* ]]
    [[ "$block" == *"audit-schema"* ]]
    [[ "$block" == *"output shape"* ]]
}

@test "probe bullet names the F1-class defect and requires a live run before locking" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"F1-class"* ]]
    [[ "$block" == *"live run"* ]]
    [[ "$block" == *"AFTER"* ]]
}

@test "probe bullet demands an inline post-live-run verdict annotation" {
    local block; block=$(bullet_block)
    [ -n "$block" ]
    [[ "$block" == *"verified post-live-run"* ]]
}
