#!/usr/bin/env bats

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
    CHECKER="$ROOT/dev-tools/check-talo-0001-workflow-contract.py"
    FIXTURE="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$FIXTURE/dev-tools" "$FIXTURE/.github/workflows"
    cp "$CHECKER" "$FIXTURE/dev-tools/"
    cp "$ROOT/dev-tools/trusted-talo-0001-replay.sh" "$FIXTURE/dev-tools/"
    cp "$ROOT/.github/workflows/talo-0001-projection-contract.yml" \
        "$ROOT/.github/workflows/talo-0001-trusted-replay.yml" \
        "$FIXTURE/.github/workflows/"
}

run_check() {
    run python3 "$FIXTURE/dev-tools/check-talo-0001-workflow-contract.py"
}

@test "trusted and projection workflow contract is MET" {
    run_check
    [ "$status" -eq 0 ] && [[ "$output" == *'talo_0001_workflow_contract=MET'* ]]
}

@test "projection no-op mutation is rejected" {
    sed -i 's#python3 dev-tools/check-talo-0001-research-projection.py#true#' \
        "$FIXTURE/.github/workflows/talo-0001-projection-contract.yml"
    run_check
    [ "$status" -eq 1 ] && [[ "$output" == *'missing:projection-command'* ]]
}

@test "trusted controller no-op and PR trigger mutations are rejected" {
    sed -i 's#trusted/dev-tools/trusted-talo-0001-replay.sh#true#; s/workflow_run:/pull_request_target:/' \
        "$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'missing:trusted-trigger'* ]] \
        && [[ "$output" == *'missing:trusted-controller-command'* ]] \
        && [[ "$output" == *'forbidden:trusted-pr-authored-trigger'* ]]
}
