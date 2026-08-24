#!/usr/bin/env bats

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
    CHECKER="$ROOT/dev-tools/check-talo-0001-workflow-contract.py"
    FIXTURE="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$FIXTURE/dev-tools" "$FIXTURE/.github/workflows"
    cp "$CHECKER" "$FIXTURE/dev-tools/"
    cp "$ROOT/dev-tools/trusted-talo-0001-replay.sh" "$FIXTURE/dev-tools/"
    cp "$ROOT/dev-tools/preflight-talo-0001-workflow-run.sh" "$FIXTURE/dev-tools/"
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

@test "each trusted pre-secret identity guard is load-bearing" {
    local controller="$FIXTURE/dev-tools/preflight-talo-0001-workflow-run.sh"
    local original="$BATS_TEST_TMPDIR/controller.original"
    cp "$controller" "$original"
    while IFS='|' read -r needle label; do
        cp "$original" "$controller"
        python3 - "$controller" "$needle" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
assert sys.argv[2] in text
path.write_text(text.replace(sys.argv[2], "REMOVED", 1), encoding="utf-8")
PY
        run_check
        [ "$status" -eq 1 ] && [[ "$output" == *"missing:${label}"* ]]
    done <<'GUARDS'
conclusion=$(jq -er|guard-conclusion
event=$(jq -er|guard-event
head_repository=$(jq -er|guard-head-repository
pr_count=$(jq -er|guard-pr-count
[[ "$head_sha" =~ ^[0-9a-f]{40}$ ]]|guard-head-sha
[ "$conclusion" != success ]|guard-success
[ "$event" != pull_request ]|guard-pull-request-event
[ "$head_repository" != Arcanada-one/datarim ]|guard-same-repository
[ "$pr_count" -ne 1 ]|guard-single-pr
GUARDS
}
