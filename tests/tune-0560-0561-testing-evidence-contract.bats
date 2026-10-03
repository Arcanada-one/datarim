#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WRAPPER="$ROOT/tests/fixtures/shell-harness-evidence/wrapper.sh"
    TMP_CASE="$(mktemp -d)"
}

teardown() {
    rm -rf -- "$TMP_CASE"
}

assert_contract_tree() {
    local root="$1"

    grep -Fq '## Gate 9: Shell-Harness Child-Failure Attribution' "$root/skills/testing/live-smoke-gates.md" || return 1
    grep -Fq '**Positive control.**' "$root/skills/testing/live-smoke-gates.md" || return 1
    grep -Fq '**Negative control.**' "$root/skills/testing/live-smoke-gates.md" || return 1
    grep -Fq 'named assertion' "$root/skills/testing/live-smoke-gates.md" || return 1
    grep -Fq 'HARNESS_INVALID' "$root/skills/testing/live-smoke-gates.md" || return 1

    grep -Fq '## Unique-Violation Domain Normalization' "$root/skills/testing/SKILL.md" || return 1
    grep -Fq 'exact named constraint' "$root/skills/testing/SKILL.md" || return 1
    grep -Fq 'exact normalized column signature' "$root/skills/testing/SKILL.md" || return 1
    grep -Fq 'unknown explicit constraint' "$root/skills/testing/SKILL.md" || return 1
    grep -Fq 'The unrelated unique violation test must then go red.' "$root/skills/testing/SKILL.md" || return 1

    grep -Fqi 'Gate 9' "$root/commands/dr-qa.md" || return 1
    grep -Fqi 'unique-violation' "$root/commands/dr-qa.md" || return 1
    grep -Fqi 'Gate 9' "$root/skills/compliance/SKILL.md" || return 1
    grep -Fqi 'unique-violation' "$root/skills/compliance/SKILL.md" || return 1
    grep -Fqi 'shell-harness' "$root/commands/dr-compliance.md" || return 1
    grep -Fqi 'unique-violation' "$root/commands/dr-compliance.md" || return 1
}

copy_contract_tree() {
    local target="$1"
    mkdir -p "$target/skills/testing" "$target/skills/compliance" "$target/commands"
    cp "$ROOT/skills/testing/live-smoke-gates.md" "$target/skills/testing/live-smoke-gates.md"
    cp "$ROOT/skills/testing/SKILL.md" "$target/skills/testing/SKILL.md"
    cp "$ROOT/skills/compliance/SKILL.md" "$target/skills/compliance/SKILL.md"
    cp "$ROOT/commands/dr-qa.md" "$target/commands/dr-qa.md"
    cp "$ROOT/commands/dr-compliance.md" "$target/commands/dr-compliance.md"
}

rewrite_file() {
    local expression="$1"
    local file="$2"
    local replacement="${file}.next"

    sed "$expression" "$file" >"$replacement" || return 1
    mv "$replacement" "$file" || return 1
}

assert_failing_child_propagates() {
    local wrapper="$1"
    local child_output child_status

    child_output=$(bash "$wrapper" bash -c 'printf "CHILD_RED\\n"; exit 23' 2>&1)
    child_status=$?
    [ "$child_status" -eq 23 ] || return 1
    [[ "$child_output" == *"CHILD_FAILURE:23"* ]] || return 1
    [[ "$child_output" != *"HARNESS_PASS"* ]] || return 1
}

assert_setup_failure_is_invalid() {
    local wrapper="$1"
    local child_output child_status

    child_output=$(EXPECTED_SENTINEL=MUTATION_CAUGHT bash "$wrapper" bash -c 'printf "FIXTURE_MISSING\\n" >&2; exit 2' 2>&1)
    child_status=$?
    [ "$child_status" -eq 65 ] || return 1
    [[ "$child_output" == *"HARNESS_INVALID:missing-sentinel:MUTATION_CAUGHT"* ]] || return 1
    [[ "$child_output" != *"EXPECTED_RED_CONFIRMED"* ]] || return 1
}

@test "passing child produces wrapper success and named pass evidence" {
    run bash "$WRAPPER" bash -c 'printf "CHILD_OK\\n"'

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"CHILD_OK"* ]] || return 1
    [[ "$output" == *"HARNESS_PASS"* ]] || return 1
}

@test "failing child remains a failure and cannot print pass evidence" {
    run bash "$WRAPPER" bash -c 'printf "CHILD_RED\\n"; exit 23'

    [ "$status" -eq 23 ] || return 1
    [[ "$output" == *"CHILD_FAILURE:23"* ]] || return 1
    [[ "$output" != *"HARNESS_PASS"* ]] || return 1
}

@test "expected-red evidence succeeds only for its named assertion" {
    EXPECTED_SENTINEL=MUTATION_CAUGHT run bash "$WRAPPER" bash -c 'printf "MUTATION_CAUGHT\\n"; exit 1'

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"EXPECTED_RED_CONFIRMED:MUTATION_CAUGHT"* ]] || return 1
}

@test "expected-red substring is not the named assertion" {
    EXPECTED_SENTINEL=MUTATION_CAUGHT run bash "$WRAPPER" bash -c 'printf "MUTATION_CAUGHT_EXTRA\\n"; exit 1'

    [ "$status" -eq 65 ] || return 1
    [[ "$output" == *"HARNESS_INVALID:missing-sentinel:MUTATION_CAUGHT"* ]] || return 1
    [[ "$output" != *"EXPECTED_RED_CONFIRMED"* ]] || return 1
}

@test "unrelated setup failure is invalid rather than mutation evidence" {
    EXPECTED_SENTINEL=MUTATION_CAUGHT run bash "$WRAPPER" bash -c 'printf "FIXTURE_MISSING\\n" >&2; exit 2'

    [ "$status" -eq 65 ] || return 1
    [[ "$output" == *"HARNESS_INVALID:missing-sentinel:MUTATION_CAUGHT"* ]] || return 1
    [[ "$output" != *"EXPECTED_RED_CONFIRMED"* ]] || return 1
}

@test "mutation swallowing the failing child status is rejected" {
    local mutant="$TMP_CASE/wrapper-swallow-status.sh"
    cp "$WRAPPER" "$mutant"
    # The mutation targets a literal shell expression, so expansion is wrong.
    # shellcheck disable=SC2016
    rewrite_file 's/exit "$child_status"/exit 0/' "$mutant"

    run assert_failing_child_propagates "$mutant"
    [ "$status" -ne 0 ] || return 1
}

@test "mutation accepting unrelated setup failure is rejected" {
    local mutant="$TMP_CASE/wrapper-accept-setup.sh"
    cp "$WRAPPER" "$mutant"
    rewrite_file '/HARNESS_INVALID:missing-sentinel/{n;s/exit 65/exit 0/;}' "$mutant"

    run assert_setup_failure_is_invalid "$mutant"
    [ "$status" -ne 0 ] || return 1
}

@test "shipped QA and compliance contracts contain both fail-hard gates" {
    assert_contract_tree "$ROOT"
}

@test "mutation removing shell negative control makes the contract test red" {
    copy_contract_tree "$TMP_CASE"
    rewrite_file 's/\*\*Negative control\.\*\*/**Removed control.**/g' "$TMP_CASE/skills/testing/live-smoke-gates.md"

    run assert_contract_tree "$TMP_CASE"
    [ "$status" -ne 0 ] || return 1
}

@test "mutation removing unrelated unique-violation case makes the contract test red" {
    copy_contract_tree "$TMP_CASE"
    rewrite_file 's/The unrelated unique violation test must then go red\./The unrelated database condition test must then go red./g' "$TMP_CASE/skills/testing/SKILL.md"

    run assert_contract_tree "$TMP_CASE"
    [ "$status" -ne 0 ] || return 1
}
