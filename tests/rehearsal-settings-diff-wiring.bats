#!/usr/bin/env bats

# Source-wiring checks for the documented settings-comparison procedure.
# They do not read live settings, inspect secrets, or exercise a prediction.

setup() {
    SKILL="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/test-env-verification/SKILL.md"
}

@test "autonomous procedure places the settings comparison before Record" {
    compare_line=$(grep -n '^5\. \*\*Compare outcome-deciding settings' "$SKILL" | cut -d: -f1)
    record_line=$(grep -n '^6\. \*\*Record\*\*' "$SKILL" | cut -d: -f1)
    [ -n "$compare_line" ] && [ -n "$record_line" ]
    [ "$compare_line" -lt "$record_line" ]
}

@test "comparison is bounded and uses authorized read-only access" {
    run grep -F -c 'through authorized, read-only access' "$SKILL"
    [ "$output" -ge 1 ]
    run grep -F -c 'minimum relevant' "$SKILL"
    [ "$output" -ge 1 ]
}

@test "secret values are never inspected, copied, or reported" {
    run grep -F -c 'Never inspect, copy, or report secret' "$SKILL"
    [ "$output" -ge 1 ]
    run grep -F -c 'redact sensitive identifiers or values' "$SKILL"
    [ "$output" -ge 1 ]
}

@test "unsafe or unavailable evidence is not measured and voids the prediction" {
    run grep -F -c 'the comparison as **NOT_MEASURED**' "$SKILL"
    [ "$output" -ge 1 ]
    skill_text=$(tr '\n' ' ' < "$SKILL")
    [[ "$skill_text" == *"production-impact prediction is void"* ]]
}

@test "the procedure authorizes no tier mutation or remote production operation" {
    run grep -F -c 'no authority to change either tier' "$SKILL"
    [ "$output" -ge 1 ]
}

@test "the QA record requires bounded redacted evidence" {
    run grep -F -c 'the bounded redacted settings' "$SKILL"
    [ "$output" -ge 1 ]
}
