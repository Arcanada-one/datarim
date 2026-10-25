#!/usr/bin/env bats

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-qa-contract-version.py"
    CONTRACT="$BATS_TEST_TMPDIR/contract.json"
    CHARTER="$BATS_TEST_TMPDIR/charter.md"
    printf '{"contract_version":"2","supersedes_version":"1"}\n' > "$CONTRACT"
}

@test "stale charter cannot certify superseding contract" {
    printf '```qa-charter-json\n{"contract_version":"1"}\n```\n' > "$CHARTER"
    run python3 "$SCRIPT" --contract "$CONTRACT" --charter "$CHARTER"
    [ "$status" -eq 1 ]
    [[ "$output" == *"same version"* ]]
}

@test "matching charter version passes the version gate" {
    printf '```qa-charter-json\n{"contract_version":"2"}\n```\n' > "$CHARTER"
    run python3 "$SCRIPT" --contract "$CONTRACT" --charter "$CHARTER"
    [ "$status" -eq 0 ]
}
