#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../validate-self-verification-findings.py"
    QA_COMMAND="${BATS_TEST_DIRNAME}/../../commands/dr-qa.md"
}

@test "legacy findings without resolution metadata remain valid" {
    payload='[{"finding_id":"F-1-1","severity":"medium","category":"correctness","ac_criteria":[],"evidence":{"type":"file_quote","source":"plan.md:1","excerpt":"required"}}]'
    run python3 "$SCRIPT" --round 1 --max-iter 3 <<< "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"ok": true'* ]]
    [[ "$output" != *'"resolution"'* ]]
}

@test "live compatibility upgrade keeps legacy findings unresolved" {
    payload='[{"finding_id":"F-floor-1","severity":"medium","category":"completeness","ac_criteria":[],"evidence":{"type":"test_output","source":"synthetic floor fixture","excerpt":"required check failed"}}]'
    run python3 "$SCRIPT" --round 2 --max-iter 3 --upgrade-legacy <<< "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"resolution": "unresolved"'* ]]
    [[ "$output" == *'"round": 2'* ]]
}

@test "all supported resolution states accept the current round" {
    payload='[{"severity":"high","category":"correctness","ac_criteria":[],"evidence":{"type":"test_output","source":"synthetic fixture","excerpt":"action required"},"resolution":"actionable","round":1},{"severity":"low","category":"safety","ac_criteria":[],"evidence":{"type":"file_quote","source":"fixture.md:1","excerpt":"advisory note"},"resolution":"advisory","round":1},{"severity":"medium","category":"completeness","ac_criteria":[],"evidence":{"type":"verified_absence","source":"synthetic lookup","excerpt":"expected fixture missing"},"resolution":"unresolved","round":1}]'
    run python3 "$SCRIPT" --round 1 --max-iter 3 <<< "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"resolution": "actionable"'* ]]
    [[ "$output" == *'"resolution": "advisory"'* ]]
    [[ "$output" == *'"resolution": "unresolved"'* ]]
}

@test "unresolved findings remain unresolved at the iteration cap" {
    payload='[{"finding_id":"F-dispatch-1","severity":"high","category":"correctness","ac_criteria":[],"evidence":{"type":"test_output","source":"synthetic fixture","excerpt":"still failing"},"resolution":"unresolved","round":3}]'
    run python3 "$SCRIPT" --round 3 --max-iter 3 <<< "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"resolution": "unresolved"'* ]]
}

@test "fixed is not an accepted resolution at the cap" {
    payload='[{"severity":"high","category":"correctness","ac_criteria":[],"evidence":{"type":"test_output","source":"synthetic fixture","excerpt":"still failing"},"resolution":"fixed","round":3}]'
    run python3 "$SCRIPT" --round 3 --max-iter 3 <<< "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *'resolution must be actionable, advisory, or unresolved'* ]]
}

@test "new records require resolution and round together and round must match" {
    payload='[{"severity":"low","category":"safety","ac_criteria":[],"evidence":{"type":"test_output","source":"synthetic fixture","excerpt":"note"},"resolution":"advisory","round":2}]'
    run python3 "$SCRIPT" --round 1 --max-iter 3 <<< "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *'round must match the current verification iteration'* ]]
}

@test "absent evidence is discarded and cannot be kept alive with confidence" {
    payload='[{"severity":"low","category":"completeness","ac_criteria":[],"evidence":{"type":"absent"},"resolution":"advisory","round":1,"confidence":0.1}]'
    run python3 "$SCRIPT" --round 1 --max-iter 3 <<< "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *'confidence is not a supported finding field'* ]]

    payload='[{"severity":"low","category":"completeness","ac_criteria":[],"evidence":{"type":"absent"},"resolution":"advisory","round":1}]'
    run python3 "$SCRIPT" --round 1 --max-iter 3 <<< "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"discarded": true'* ]]
    [[ "$output" == *'"discard_reason": "no_evidence_provided"'* ]]
}

@test "verified_absence remains evidence and is never discarded" {
    payload='[{"severity":"medium","category":"completeness","ac_criteria":[],"evidence":{"type":"verified_absence","source":"synthetic file scan","excerpt":"file absent"}}]'
    run python3 "$SCRIPT" --round 1 --max-iter 3 <<< "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"discarded": false'* ]]

    payload='[{"severity":"medium","category":"completeness","ac_criteria":[],"evidence":{"type":"verified_absence","source":"synthetic file scan","excerpt":"file absent"},"discarded":true}]'
    run python3 "$SCRIPT" --round 1 --max-iter 3 <<< "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *'verified_absence is evidence and must not be discarded'* ]]
}

@test "consistency subtype is optional only for consistency findings" {
    payload='[{"severity":"low","category":"safety","drift_subtype":"scope_creep","ac_criteria":[],"evidence":{"type":"file_quote","source":"file:1","excerpt":"quote"}}]'
    run python3 "$SCRIPT" --round 1 --max-iter 3 <<< "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *'drift_subtype must be absent unless category is consistency'* ]]

    payload='[{"severity":"low","category":"consistency","ac_criteria":[],"evidence":{"type":"file_quote","source":"file:1","excerpt":"quote"}}]'
    run python3 "$SCRIPT" --round 1 --max-iter 3 <<< "$payload"
    [ "$status" -eq 0 ]

    payload='[{"severity":"low","category":"consistency","drift_subtype":"other","ac_criteria":[],"evidence":{"type":"file_quote","source":"file:1","excerpt":"quote"}}]'
    run python3 "$SCRIPT" --round 1 --max-iter 3 <<< "$payload"
    [ "$status" -eq 1 ]
}

@test "evidence-backed findings require source and excerpt" {
    payload='[{"severity":"low","category":"correctness","ac_criteria":[],"evidence":{"type":"file_quote","excerpt":"quote"}}]'
    run python3 "$SCRIPT" --round 1 --max-iter 3 <<< "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *'evidence.source is required'* ]]
}

@test "long excerpts are truncated to the established limit" {
    payload="$(python3 -c 'import json; print(json.dumps([{"severity":"low","category":"correctness","ac_criteria":[],"evidence":{"type":"file_quote","source":"file:1","excerpt":"x"*240}}]))')"
    run python3 "$SCRIPT" --round 1 --max-iter 3 <<< "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *'[truncated]'* ]]
}

@test "severity is a strict enum" {
    payload='[{"severity":"critical","category":"correctness","ac_criteria":[],"evidence":{"type":"test_output","source":"synthetic fixture","excerpt":"note"}}]'
    run python3 "$SCRIPT" --round 1 --max-iter 3 <<< "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *'severity must be high, medium, or low'* ]]
}

@test "ac_criteria must be an array" {
    payload='[{"severity":"low","category":"correctness","ac_criteria":"AC-1","evidence":{"type":"test_output","source":"synthetic fixture","excerpt":"note"}}]'
    run python3 "$SCRIPT" --round 1 --max-iter 3 <<< "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *'ac_criteria must be an array'* ]]
}

@test "suggested_fix retains its 500 character limit" {
    payload="$(python3 -c 'import json; print(json.dumps([{"severity":"low","category":"correctness","ac_criteria":[],"evidence":{"type":"test_output","source":"synthetic fixture","excerpt":"note"},"suggested_fix":"x"*501}]))')"
    run python3 "$SCRIPT" --round 1 --max-iter 3 <<< "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *'suggested_fix must be a string of at most 500 characters'* ]]
}

@test "dr-qa Layer 3 consumes all five statuses and discrepancy reasons" {
    for status_name in DONE PARTIAL 'NOT DONE' CHANGED UNVERIFIABLE; do
        [[ "$(cat "$QA_COMMAND")" == *"$status_name"* ]]
    done
    for reason in 'scope cut' 'context exhaustion' misunderstood blocked forgotten; do
        [[ "$(cat "$QA_COMMAND")" == *"$reason"* ]]
    done
    [[ "$(cat "$QA_COMMAND")" == *'code that handles or generates a deliverable does not make the deliverable `DONE`'* ]]
}

@test "dr-verify invokes the executable validator and upgrades legacy producer output" {
    command_file="${BATS_TEST_DIRNAME}/../../commands/dr-verify.md"
    grep -Fq 'validate-self-verification-findings.py' "$command_file"
    grep -Fq -- '--upgrade-legacy' "$command_file"
    grep -Fq 'finding_schema_invalid' "$command_file"
}
