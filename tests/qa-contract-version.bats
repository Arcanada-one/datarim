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

@test "summary preserves a successful existing supersession match" {
    printf '```qa-charter-json\n{"contract_version":"2"}\n```\n' > "$CHARTER"
    run python3 "$SCRIPT" --contract "$CONTRACT" --charter "$CHARTER" --summary-json
    [ "$status" -eq 0 ]
    [ "$output" = '{"schema":"DatarimQaContractVersionSummary/v1","result":"PASS","exit_code":0,"version_binding":"MATCHED","diagnostic_codes":[]}' ]
}

@test "summary keeps unrelated charter version valid when supersession is absent" {
    printf '{"contract_version":"2"}\n' > "$CONTRACT"
    printf '```qa-charter-json\n{"contract_version":"other"}\n```\n' > "$CHARTER"
    run python3 "$SCRIPT" --contract "$CONTRACT" --charter "$CHARTER" --summary-json
    [ "$status" -eq 0 ]
    [ "$output" = '{"schema":"DatarimQaContractVersionSummary/v1","result":"PASS","exit_code":0,"version_binding":"NOT_REQUIRED","diagnostic_codes":[]}' ]
}

@test "summary refuses an existing supersession mismatch with fixed diagnostics" {
    printf '```qa-charter-json\n{"contract_version":"other"}\n```\n' > "$CHARTER"
    run python3 "$SCRIPT" --contract "$CONTRACT" --charter "$CHARTER" --summary-json
    [ "$status" -eq 1 ]
    [ "$output" = '{"schema":"DatarimQaContractVersionSummary/v1","result":"FAIL","exit_code":1,"version_binding":"NOT_MEASURED","diagnostic_codes":["CHARTER_VERSION_MISMATCH"]}' ]
}
