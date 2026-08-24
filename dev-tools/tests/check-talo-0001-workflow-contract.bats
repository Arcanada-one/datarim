#!/usr/bin/env bats

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
    CHECKER="$ROOT/dev-tools/check-talo-0001-workflow-contract.py"
    FIXTURE="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$FIXTURE/dev-tools/systemd" "$FIXTURE/.github/workflows"
    cp "$CHECKER" "$FIXTURE/dev-tools/"
    cp "$ROOT/dev-tools/trusted-talo-0001-replay.sh" "$FIXTURE/dev-tools/"
    cp "$ROOT/dev-tools/preflight-talo-0001-workflow-run.sh" "$FIXTURE/dev-tools/"
    cp "$ROOT/dev-tools/publish-talo-0001-check.sh" "$FIXTURE/dev-tools/"
    cp "$ROOT/dev-tools/check-talo-0001-trusted-authority.py" "$FIXTURE/dev-tools/"
    cp "$ROOT/dev-tools/provision-talo-0001-trusted-runner.sh" "$FIXTURE/dev-tools/"
    cp "$ROOT/dev-tools/systemd/talo-0001-trusted-runner.service" \
        "$FIXTURE/dev-tools/systemd/"
    cp "$ROOT/.github/workflows/dev-tools-lint.yml" \
        "$FIXTURE/.github/workflows/"
    cp "$ROOT/.github/workflows/talo-0001-trusted-replay.yml" \
        "$FIXTURE/.github/workflows/"
    if [ -f "$ROOT/.github/actionlint.yaml" ]; then
        cp "$ROOT/.github/actionlint.yaml" "$FIXTURE/.github/"
    fi
}

teardown() {
    if [ -n "${RUNNER_FIXTURE:-}" ] \
        && [[ "$RUNNER_FIXTURE" == "$BATS_TEST_TMPDIR/"* ]] \
        && [ -e "$RUNNER_FIXTURE" ]; then
        sudo chown -R "$(id -u):$(id -g)" "$RUNNER_FIXTURE"
    fi
}

run_check() {
    run python3 "$FIXTURE/dev-tools/check-talo-0001-workflow-contract.py"
}

setup_provision_runtime() {
    PROVISIONER="$FIXTURE/dev-tools/provision-talo-0001-trusted-runner.sh"
    MOCK_BIN="$BATS_TEST_TMPDIR/provision-mock-bin"
    MOCK_LOG="$BATS_TEST_TMPDIR/provision-commands.log"
    RUNNER_FIXTURE="$BATS_TEST_TMPDIR/runner"
    mkdir -p "$MOCK_BIN" "$RUNNER_FIXTURE/bin" "$RUNNER_FIXTURE/externals"
    for command in chmod chown curl gh install sudo systemctl sleep; do
        ln -sf "$ROOT/dev-tools/tests/fixtures/talo-0001-command-mock.sh" \
            "$MOCK_BIN/$command"
    done
    sed -i "s#RUNNER_DIR=/srv/talo-0001-trusted/runner#RUNNER_DIR=$RUNNER_FIXTURE#" \
        "$PROVISIONER"
    cat >"$RUNNER_FIXTURE/config.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'config.sh %s\n' "$*" >>"${TALO_MOCK_LOG:?}"
cd "$(dirname "$0")"
if [ "${1:-}" = remove ]; then
    rm -f -- .runner .credentials .credentials_rsaparams .env .path
    exit 0
fi
cat >.runner <<'JSON'
{"AgentId":7001,"AgentName":"talo-0001-trusted-arcana-devs","PoolId":42,"PoolName":"talo-0001-trusted","DisableUpdate":true,"Ephemeral":false,"GitHubUrl":"https://github.com/Arcanada-one","WorkFolder":"_work"}
JSON
[ "${TALO_MOCK_CONFIG_FAILURE:-0}" != 1 ]
SH
    chmod +x "$RUNNER_FIXTURE/config.sh"
    printf '%s\n' fixture-run >"$RUNNER_FIXTURE/run.sh"
    printf '%s\n' fixture-listener >"$RUNNER_FIXTURE/bin/Runner.Listener"
    printf '%s\n' fixture-worker >"$RUNNER_FIXTURE/bin/Runner.Worker"
    printf '%s\n' fixture-support >"$RUNNER_FIXTURE/externals/support.bin"
    for payload_file in env.sh run-helper.cmd.template run-helper.sh.template safe_sleep.sh; do
        printf '%s\n' "fixture-$payload_file" >"$RUNNER_FIXTURE/$payload_file"
    done
    while IFS='|' read -r constant relative; do
        digest="$(sha256sum "$RUNNER_FIXTURE/$relative")"
        digest="${digest%% *}"
        sed -i -E "s#^${constant}=[0-9a-f]{64}#${constant}=${digest}#" "$PROVISIONER"
    done <<'DIGESTS'
RUNNER_CONFIG_SHA256|config.sh
RUNNER_SCRIPT_SHA256|run.sh
RUNNER_LISTENER_SHA256|bin/Runner.Listener
RUNNER_WORKER_SHA256|bin/Runner.Worker
DIGESTS
    tree_digest=$(
        (
            cd "$RUNNER_FIXTURE"
            {
                find bin externals -print0
                printf '%s\0' config.sh env.sh run.sh run-helper.cmd.template \
                    run-helper.sh.template safe_sleep.sh
            } | LC_ALL=C sort -z | while IFS= read -r -d '' relative; do
                if [ -L "$relative" ]; then
                    printf 'L\0%s\0%s\0' "$relative" "$(readlink -- "$relative")"
                elif [ -f "$relative" ]; then
                    digest=$(sha256sum -- "$relative")
                    digest=${digest%% *}
                    printf 'F\0%s\0%s\0' "$relative" "$digest"
                elif [ -d "$relative" ]; then
                    printf 'D\0%s\0' "$relative"
                else
                    exit 1
                fi
            done
        ) | sha256sum
    )
    tree_digest=${tree_digest%% *}
    sed -i -E \
        "s#^RUNNER_PAYLOAD_TREE_SHA256=[0-9a-f]{64}#RUNNER_PAYLOAD_TREE_SHA256=$tree_digest#" \
        "$PROVISIONER"
    cat >"$RUNNER_FIXTURE/.runner" <<'JSON'
{"AgentId":7001,"AgentName":"talo-0001-trusted-arcana-devs","PoolId":42,"PoolName":"talo-0001-trusted","DisableUpdate":true,"Ephemeral":false,"GitHubUrl":"https://github.com/Arcanada-one","WorkFolder":"_work"}
JSON
    MOCK_BLOB="$(git hash-object "$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml")"
    MOCK_UNIT_BLOB="$(git hash-object "$FIXTURE/dev-tools/systemd/talo-0001-trusted-runner.service")"
    MOCK_SERVICE_STATE="$BATS_TEST_TMPDIR/provision-service-state"
    MOCK_REGISTRATION_REMOVED="$BATS_TEST_TMPDIR/registration-removed"
    : >"$MOCK_LOG"
    rm -f -- "$MOCK_REGISTRATION_REMOVED"
    printf '%s\n' enabled >"$MOCK_SERVICE_STATE"
}

prepare_fresh_runner_payload() {
    local archive_source="$BATS_TEST_TMPDIR/archive-source"
    MOCK_ARCHIVE="$BATS_TEST_TMPDIR/actions-runner.tar.gz"
    mkdir -p "$archive_source"
    cp -a "$RUNNER_FIXTURE/." "$archive_source/"
    rm -f -- "$archive_source/.runner"
    tar -czf "$MOCK_ARCHIVE" -C "$archive_source" .
    archive_digest=$(sha256sum "$MOCK_ARCHIVE")
    archive_digest=${archive_digest%% *}
    sed -i -E \
        "s#^RUNNER_ARCHIVE_SHA256=[0-9a-f]{64}#RUNNER_ARCHIVE_SHA256=$archive_digest#" \
        "$PROVISIONER"
    rm -rf -- "$RUNNER_FIXTURE"
}

run_provision_runtime() {
    MOCK_PROVISIONER_BLOB="${TALO_MOCK_PROVISIONER_BLOB_OVERRIDE:-$(git hash-object "$PROVISIONER")}"
    run sudo env "PATH=$MOCK_BIN:$PATH" \
        "TALO_MOCK_LOG=$MOCK_LOG" \
        "TALO_MOCK_GH_MODE=${TALO_MOCK_GH_MODE:-success}" \
        "TALO_MOCK_BLOB=$MOCK_BLOB" \
        "TALO_MOCK_PROVISIONER_BLOB=$MOCK_PROVISIONER_BLOB" \
        "TALO_MOCK_UNIT_BLOB=$MOCK_UNIT_BLOB" \
        "TALO_MOCK_RUNNERS_MODE=${TALO_MOCK_RUNNERS_MODE:-one}" \
        "TALO_MOCK_STOP_FAILURE=${TALO_MOCK_STOP_FAILURE:-0}" \
        "TALO_MOCK_ENABLE_FAILURE=${TALO_MOCK_ENABLE_FAILURE:-0}" \
        "TALO_MOCK_CONFIG_FAILURE=${TALO_MOCK_CONFIG_FAILURE:-0}" \
        "TALO_MOCK_ENFORCE_TRAVERSAL=${TALO_MOCK_ENFORCE_TRAVERSAL:-0}" \
        "TALO_MOCK_ARCHIVE=${MOCK_ARCHIVE:-}" \
        "TALO_MOCK_RUNNER_DIR=$RUNNER_FIXTURE" \
        "TALO_MOCK_SERVICE_STATE=$MOCK_SERVICE_STATE" \
        "TALO_MOCK_REGISTRATION_REMOVED=$MOCK_REGISTRATION_REMOVED" \
        "$PROVISIONER" --register-and-start
}

@test "trusted and projection workflow contract is MET" {
    run_check
    [ "$status" -eq 0 ] && [[ "$output" == *'talo_0001_workflow_contract=MET'* ]]
}

@test "projection no-op mutation is rejected" {
    sed -i 's|python3 dev-tools/check-talo-0001-research-projection.py --if-present|true|' \
        "$FIXTURE/.github/workflows/dev-tools-lint.yml"
    run_check
    [ "$status" -eq 1 ] && [[ "$output" == *'mismatch:projection-job'* ]]
}

@test "trusted controller no-op and PR trigger mutations are rejected" {
    sed -i 's#trusted/dev-tools/trusted-talo-0001-replay.sh#true#; s/workflow_run:/pull_request_target:/' \
        "$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'mismatch:trusted-trigger'* ]] \
        && [[ "$output" == *'mismatch:trusted-job'* ]]
}

@test "trusted workflow has no unused pull-request permission" {
    local trusted="$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml"
    run grep -q 'pull-requests:' "$trusted"
    [ "$status" -ne 0 ]
    sed -i '/permissions:/a\  pull-requests: read' "$trusted"
    run_check
    [ "$status" -eq 1 ] && [[ "$output" == *'mismatch:trusted-permissions'* ]]
}

@test "trusted replay requires the exact workflow-scoped runner group" {
    local workflow="$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml"
    local original="$BATS_TEST_TMPDIR/trusted-group.original"
    cp "$workflow" "$original"

    sed -i '/      group: talo-0001-trusted/d' "$workflow"
    run_check
    [ "$status" -eq 1 ] && [[ "$output" == *'mismatch:trusted-job'* ]]

    cp "$original" "$workflow"
    sed -i 's/group: talo-0001-trusted/group: Default/' "$workflow"
    run_check
    [ "$status" -eq 1 ] && [[ "$output" == *'mismatch:trusted-job'* ]]
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
        [ "$status" -eq 1 ] \
            && [[ "$output" == *'digest_mismatch:preflight'* ]]
    done <<'GUARDS'
conclusion=$(jq -er|guard-conclusion
event=$(jq -er|guard-event
head_repository=$(jq -er|guard-head-repository
repository=$(jq -er|guard-repository
workflow_id=$(jq -er|guard-workflow-id
workflow_name=$(jq -er|guard-workflow-name
workflow_path=$(jq -er|guard-workflow-path
pr_head_sha=$(jq -er|guard-pr-head-sha
pr_number=$(jq -er|guard-pr-number
pr_head_ref=$(jq -er|guard-pr-head-ref
pr_head_repository=$(jq -er|guard-pr-head-repository
pr_base_ref=$(jq -er|guard-pr-base-ref
pr_base_repository=$(jq -er|guard-pr-base-repository
pr_count=$(jq -er|guard-pr-count
[[ "$head_sha" =~ ^[0-9a-f]{40}$ ]]|guard-head-sha
[ "$conclusion" != success ]|guard-success
[ "$event" != pull_request ]|guard-pull-request-event
[ "$head_repository" != Arcanada-one/datarim ]|guard-same-repository
[ "$repository" != Arcanada-one/datarim ]|guard-workflow-repository
[ "$workflow_id" -ne 270931528 ]|guard-workflow-id-value
[ "$workflow_name" != dev-tools-lint ]|guard-workflow-name-value
[ "$workflow_path" != .github/workflows/dev-tools-lint.yml ]|guard-workflow-path-value
[ "$head_sha" != "$pr_head_sha" ]|guard-workflow-pr-head-match
[ "$pr_number" -ne 394 ]|guard-pr-number-value
[ "$pr_head_ref" != research/TALO-0001-frontend-design ]|guard-pr-head-ref-value
[ "$pr_head_repository" != Arcanada-one/datarim ]|guard-pr-head-repository-value
[ "$pr_base_ref" != main ]|guard-pr-base-main
[ "$pr_base_repository" != Arcanada-one/datarim ]|guard-pr-base-repository-value
[ "$pr_count" -ne 1 ]|guard-single-pr
GUARDS
}

@test "workflow YAML is strict and command comments cannot satisfy the contract" {
    local trusted="$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml"
    python3 - "$trusted" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("checks: write", "checks: write\n  contents: write", 1)
text = text.replace(
    "trusted/dev-tools/trusted-talo-0001-replay.sh",
    "true # trusted/dev-tools/trusted-talo-0001-replay.sh",
    1,
)
text += "\npermissions:\n  contents: read\n"
path.write_text(text, encoding="utf-8")
PY
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *'invalid_yaml:trusted:duplicate key'* ]]
}

@test "actionlint custom runner label is closed and load-bearing" {
    local config="$FIXTURE/.github/actionlint.yaml"
    if [ -f "$config" ]; then
        sed -i '/talo-0001-trusted/d' "$config"
    fi
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'mismatch:actionlint-labels'* ]]
}

@test "projection trigger rejects push schedule and workflow-dispatch broadening" {
    local workflow="$FIXTURE/.github/workflows/dev-tools-lint.yml"
    local original="$BATS_TEST_TMPDIR/dev-tools-lint-trigger.original"
    cp "$workflow" "$original"
    while IFS= read -r trigger; do
        cp "$original" "$workflow"
        python3 - "$workflow" "$trigger" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = "permissions:\n"
assert needle in text
path.write_text(text.replace(needle, f"  {sys.argv[2]}: {{}}\n\npermissions:\n", 1), encoding="utf-8")
PY
        run_check
        [ "$status" -eq 1 ] \
            && [[ "$output" == *'mismatch:projection-trigger'* ]]
    done <<'TRIGGERS'
push
schedule
workflow_dispatch
TRIGGERS
}

@test "pull-request event mapping cannot exclude synchronize exact-head updates" {
    local workflow="$FIXTURE/.github/workflows/dev-tools-lint.yml"
    sed -i '/  pull_request:/a\    types: [opened]' "$workflow"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'mismatch:projection-pull-request'* ]]
}

@test "projection paths are exact ordered and unique" {
    local workflow="$FIXTURE/.github/workflows/dev-tools-lint.yml"
    sed -i "/      - '.github\/actionlint.yaml'/a\      - '.github/actionlint.yaml'" \
        "$workflow"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'mismatch:projection-paths'* ]]
}

@test "projection concurrency always cancels stale heads" {
    local workflow="$FIXTURE/.github/workflows/dev-tools-lint.yml"
    sed -i 's/cancel-in-progress: true/cancel-in-progress: false/' "$workflow"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'mismatch:projection-concurrency'* ]]
}

@test "all TALO trust files are load-bearing projection paths" {
    local workflow="$FIXTURE/.github/workflows/dev-tools-lint.yml"
    local original="$BATS_TEST_TMPDIR/dev-tools-lint.original"
    cp "$workflow" "$original"
    while IFS= read -r path; do
        cp "$original" "$workflow"
        python3 - "$workflow" "$path" <<'PY'
from pathlib import Path
import sys

workflow = Path(sys.argv[1])
needle = f"      - '{sys.argv[2]}'\n"
text = workflow.read_text(encoding="utf-8")
assert needle in text
workflow.write_text(text.replace(needle, "", 1), encoding="utf-8")
PY
        run_check
        [ "$status" -eq 1 ] && [[ "$output" == *'mismatch:projection-paths'* ]]
    done <<'PATHS'
datarim/insights/INSIGHTS-TALO-0001.md
datarim/insights/TALO-0001-research-authority-audit.json
dev-tools/**
.github/workflows/dev-tools-lint.yml
.github/workflows/talo-0001-trusted-replay.yml
.github/actionlint.yaml
PATHS
}

@test "candidate evaluator substitution and authority digest weakening are rejected" {
    local controller="$FIXTURE/dev-tools/trusted-talo-0001-replay.sh"
    sed -i \
        's#/trusted/dev-tools/check-talo-0001-trusted-authority.py#/candidate/dev-tools/check-research-authority-audit.py#' \
        "$controller"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'missing:trusted-evaluator-command'* ]]

    cp "$ROOT/dev-tools/trusted-talo-0001-replay.sh" "$controller"
    sed -i '/TRUSTED_EVALUATOR_SHA256=/d' "$controller"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'missing:trusted-evaluator-digest'* ]]
}

@test "trusted validator requires exact ordered complete diagnostics" {
    local controller="$FIXTURE/dev-tools/trusted-talo-0001-replay.sh"
    sed -i 's/cmp -s -- "$expected" "$result"/grep -Fqx -- "$expected_text" "$result"/' \
        "$controller"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'missing:exact-validator-output-comparison'* ]] \
        && [[ "$output" == *'forbidden:partial-validator-output-comparison'* ]]
}

@test "all seven sealed mutants preserve cardinality and remain load-bearing" {
    local controller="$FIXTURE/dev-tools/trusted-talo-0001-replay.sh"
    sed -i \
        's/.mapping_source_git_blob)=\"0000000000000000000000000000000000000000\"/.id)=\"R1\"/' \
        "$controller"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'missing:sealed-mutant-contract:'* ]] \
        && [[ "$output" == *'digest_mismatch:controller'* ]]
}

@test "sandbox identity is the dedicated non-root runner identity" {
    local controller="$FIXTURE/dev-tools/trusted-talo-0001-replay.sh"
    sed -i 's/\[ "$sandbox_uid" -ne 0 \]/true/' "$controller"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'digest_mismatch:controller'* ]]
}

@test "root-owned knowledge store uses command-scoped safe-directory" {
    local controller="$FIXTURE/dev-tools/trusted-talo-0001-replay.sh"
    sed -i 's/-c safe.directory="$KNOWLEDGE_ROOT" //' "$controller"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'digest_mismatch:controller'* ]]
}

@test "dedicated runner identity, fixed paths, and hardening are load-bearing" {
    local unit="$FIXTURE/dev-tools/systemd/talo-0001-trusted-runner.service"
    sed -i \
        -e 's/User=talo-replay/User=ci-isolated/' \
        -e '/NoNewPrivileges=true/d' \
        -e '/ReadOnlyPaths=\/srv\/talo-0001-trusted\/knowledge/d' \
        "$unit"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'digest_mismatch:runner-unit'* ]]
}

@test "runner group scope and registration-before-service order are load-bearing" {
    local provisioner="$FIXTURE/dev-tools/provision-talo-0001-trusted-runner.sh"
    local original="$BATS_TEST_TMPDIR/provisioner.original"
    cp "$provisioner" "$original"
    while IFS='|' read -r old new expected; do
        cp "$original" "$provisioner"
        sed -i "s#$old#$new#" "$provisioner"
        run_check
        [ "$status" -eq 1 ] && [[ "$output" == *"$expected"* ]]
    done <<'MUTANTS'
GROUP_NAME=talo-0001-trusted|GROUP_NAME=Default|missing:runner-group-contract
REPOSITORY_ID=1207050134|REPOSITORY_ID=999|missing:runner-group-contract
WORKFLOW_PATH=.github/workflows/talo-0001-trusted-replay.yml|WORKFLOW_PATH=.github/workflows/other.yml|missing:runner-group-contract
.restricted_to_workflows == true|.restricted_to_workflows == false|missing:runner-group-contract
systemctl stop "$UNIT_NAME"|true|mismatch:registration-safety-order
id=$(ensure_group)|id=1|mismatch:registration-safety-order
runner=$(wait_for_exact_runner "$id" registered)|runner=true|mismatch:registration-safety-order
MUTANTS
}

@test "closed runner identity payload and direct listener pins are load-bearing" {
    local provisioner="$FIXTURE/dev-tools/provision-talo-0001-trusted-runner.sh"
    local unit="$FIXTURE/dev-tools/systemd/talo-0001-trusted-runner.service"
    local original="$BATS_TEST_TMPDIR/runtime-contract.original"
    cp "$provisioner" "$original"
    while IFS='|' read -r old new; do
        cp "$original" "$provisioner"
        sed -i "s#$old#$new#" "$provisioner"
        run_check
        [ "$status" -eq 1 ] \
            && [[ "$output" == *'missing:runner-runtime-contract:'* ]]
    done <<'MUTANTS'
($document.total_count == 1)|($document.total_count >= 1)
.AgentId == $runner_id|true
RUNNER_ARCHIVE_SHA256=04cf0be1aff4c3ec3554466c39124ca250e3effd8873bb7e8d68535aa9505d5d|RUNNER_ARCHIVE_SHA256=0000000000000000000000000000000000000000000000000000000000000000
RUNNER_PAYLOAD_TREE_SHA256=802a94df6d2aee3e458620b5a1175f8646f195092081d3285b8b0dd33c8cc8f6|RUNNER_PAYLOAD_TREE_SHA256=0000000000000000000000000000000000000000000000000000000000000000
--disableupdate|--replace
install -d -o root -g root -m 0755 "$RUNNER_DIR"|install -d -o "$RUNNER_USER" -g "$RUNNER_USER" -m 0755 "$RUNNER_DIR"
systemctl disable --now "$UNIT_NAME"|systemctl stop "$UNIT_NAME"
api --method DELETE "orgs/$ORG/actions/runners/$cleanup_runner_id"|true
fresh_registration=true|fresh_registration=false
MUTANTS

    sed -i \
        's#ExecStart=/srv/talo-0001-trusted/runner/bin/Runner.Listener run#ExecStart=/srv/talo-0001-trusted/runner/run.sh#' \
        "$unit"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'missing:runner-unit:ExecStart='* ]]
}

@test "every local bootstrap artifact must be the exact main blob before mutation" {
    setup_provision_runtime
    TALO_MOCK_PROVISIONER_BLOB_OVERRIDE=0000000000000000000000000000000000000000 \
        run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'trusted provisioner is not the exact local bootstrap on main'* ]]
    ! grep -q '^systemctl ' "$MOCK_LOG"

    setup_provision_runtime
    MOCK_UNIT_BLOB=0000000000000000000000000000000000000000 \
        run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'trusted runner-unit is not the exact local bootstrap on main'* ]]
    ! grep -q '^systemctl ' "$MOCK_LOG"
}

@test "main-workflow API and blob failures perform no system mutation" {
    local mock_bin="$BATS_TEST_TMPDIR/mock-bin"
    local mock="$ROOT/dev-tools/tests/fixtures/talo-0001-command-mock.sh"
    mkdir -p "$mock_bin"
    for command in gh install sudo systemctl; do
        ln -s "$mock" "$mock_bin/$command"
    done
    for mode in api-failure wrong-blob; do
        local log="$BATS_TEST_TMPDIR/command-$mode.log"
        run sudo env "PATH=$mock_bin:$PATH" "TALO_MOCK_LOG=$log" \
            "TALO_MOCK_GH_MODE=$mode" \
            "$ROOT/dev-tools/provision-talo-0001-trusted-runner.sh" \
            --register-and-start
        [ "$status" -eq 1 ]
        [[ "$output" == *'ERROR: trusted workflow'* ]]
        ! grep -q '^systemctl ' "$log"
    done
}

@test "exact registered runner reaches online idle service success" {
    setup_provision_runtime
    run_provision_runtime
    [ "$status" -eq 0 ]
    grep -q '^systemctl stop' "$MOCK_LOG"
    grep -q '^systemctl enable --now' "$MOCK_LOG"
    [ "$(grep -c 'runner-groups/42/runners' "$MOCK_LOG")" -eq 2 ]
}

@test "trusted group rejects every extra member even when its labels match" {
    setup_provision_runtime
    TALO_MOCK_RUNNERS_MODE=extra run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'runner is not the exact trusted group member'* ]]
    ! grep -q '^systemctl enable' "$MOCK_LOG"
}

@test "local runner identity and official payload are bound before service mutation" {
    setup_provision_runtime
    sed -i 's/"AgentId":7001/"AgentId":9999/' "$RUNNER_FIXTURE/.runner"
    run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'local runner registration mismatch'* ]]
    ! grep -q '^systemctl stop' "$MOCK_LOG"

    setup_provision_runtime
    printf '%s\n' tampered-support >"$RUNNER_FIXTURE/externals/support.bin"
    run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'runner payload tree mismatch'* ]]
    ! grep -q '^systemctl stop' "$MOCK_LOG"
}

@test "registration stop failure is fatal before runner configuration" {
    setup_provision_runtime
    TALO_MOCK_STOP_FAILURE=1 run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'unable to stop trusted runner service'* ]]
    grep -q '^systemctl disable --now' "$MOCK_LOG"
    [ "$(cat "$MOCK_SERVICE_STATE")" = disabled ]
    ! grep -q 'config.sh' "$MOCK_LOG"
}

@test "post-start success requires the exact group member online and idle" {
    setup_provision_runtime
    TALO_MOCK_RUNNERS_MODE=busy run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'trusted runner did not become online and idle'* ]]
    grep -q '^systemctl disable --now' "$MOCK_LOG"
    [ "$(cat "$MOCK_SERVICE_STATE")" = disabled ]
}

@test "fresh bootstrap never traverses a root-private staging parent as runner user" {
    setup_provision_runtime
    prepare_fresh_runner_payload
    TALO_MOCK_RUNNERS_MODE=fresh TALO_MOCK_ENFORCE_TRAVERSAL=1 \
        run_provision_runtime
    [ "$status" -eq 0 ]
    grep -q '^config.sh --unattended' "$MOCK_LOG"
    ! grep -q '^sudo .*talo-runner-payload' "$MOCK_LOG"
}

@test "fresh registration timeout removes local and remote partial registration" {
    setup_provision_runtime
    prepare_fresh_runner_payload
    TALO_MOCK_RUNNERS_MODE=fresh-timeout run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'runner registration did not reach the exact trusted group'* ]]
    grep -q '^systemctl disable --now' "$MOCK_LOG"
    [ ! -e "$RUNNER_FIXTURE/.runner" ]
    [ "$(cat "$MOCK_SERVICE_STATE")" = disabled ]
}

@test "partial service enable failure disables reboot and removes fresh registration" {
    setup_provision_runtime
    prepare_fresh_runner_payload
    TALO_MOCK_RUNNERS_MODE=fresh TALO_MOCK_ENABLE_FAILURE=1 \
        run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'trusted runner service start failed'* ]]
    grep -q '^systemctl disable --now' "$MOCK_LOG"
    [ -f "$MOCK_REGISTRATION_REMOVED" ]
    [ ! -e "$RUNNER_FIXTURE/.runner" ]
    [ "$(cat "$MOCK_SERVICE_STATE")" = disabled ]
}

@test "staging and transactional rollback mutants are killed behaviorally" {
    setup_provision_runtime
    prepare_fresh_runner_payload
    local original="$BATS_TEST_TMPDIR/provisioner-transaction.original"
    cp "$PROVISIONER" "$original"
    sed -i \
        's#if ! tar --extract#if ! sudo -u "$RUNNER_USER" -- tar --extract#' \
        "$PROVISIONER"
    TALO_MOCK_RUNNERS_MODE=fresh TALO_MOCK_ENFORCE_TRAVERSAL=1 \
        run_provision_runtime
    [ "$status" -eq 1 ]

    sudo chown -R "$(id -u):$(id -g)" "$RUNNER_FIXTURE"
    setup_provision_runtime
    cp "$original" "$PROVISIONER"
    sed -i \
        's/    disable_runner_service || rollback_failed=true/    true/' \
        "$PROVISIONER"
    TALO_MOCK_RUNNERS_MODE=busy run_provision_runtime
    [ "$status" -eq 1 ]
    [ "$(cat "$MOCK_SERVICE_STATE")" = enabled ]

    sudo chown -R "$(id -u):$(id -g)" "$RUNNER_FIXTURE"
    setup_provision_runtime
    cp "$original" "$PROVISIONER"
    prepare_fresh_runner_payload
    python3 - "$PROVISIONER" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
old = '''    if [ "$fresh_registration" = true ]; then
        rollback_new_registration "$id" "$known_runner_id" \\
            || rollback_failed=true
    fi
'''
new = '''    if [ "$fresh_registration" = true ]; then
        true
    fi
'''
assert source.count(old) == 1
path.write_text(source.replace(old, new), encoding="utf-8")
PY
    TALO_MOCK_RUNNERS_MODE=fresh TALO_MOCK_ENABLE_FAILURE=1 \
        run_provision_runtime
    [ "$status" -eq 1 ]
    [ -e "$RUNNER_FIXTURE/.runner" ]
    [ ! -e "$MOCK_REGISTRATION_REMOVED" ]
    printf '%s\n' 'RED_SENTINEL:runner-transactional-rollback'
}

@test "membership cardinality mutant is killed by the behavioral boundary" {
    setup_provision_runtime
    sed -i \
        -e 's/($document.total_count == 1)/($document.total_count >= 1)/' \
        -e 's/(($document.runners | length) == 1)/(($document.runners | length) >= 1)/' \
        -e 's/"status":"offline"/"status":"online"/' \
        "$PROVISIONER"
    TALO_MOCK_RUNNERS_MODE=extra run_provision_runtime
    [ "$status" -eq 0 ]
    printf '%s\n' 'RED_SENTINEL:runner-membership-cardinality'
}

@test "local identity and payload digest mutants are killed behaviorally" {
    setup_provision_runtime
    local original="$BATS_TEST_TMPDIR/provisioner-identity.original"
    cp "$PROVISIONER" "$original"
    sed -i 's/.AgentId == $runner_id/true/' "$PROVISIONER"
    sed -i 's/"AgentId":7001/"AgentId":9999/' "$RUNNER_FIXTURE/.runner"
    run_provision_runtime
    [ "$status" -eq 0 ]

    cp "$original" "$PROVISIONER"
    sed -i 's/\[ "$actual" = "$RUNNER_PAYLOAD_TREE_SHA256" \]/true/' "$PROVISIONER"
    sed -i 's/"AgentId":9999/"AgentId":7001/' "$RUNNER_FIXTURE/.runner"
    printf '%s\n' tampered-support >"$RUNNER_FIXTURE/externals/support.bin"
    run_provision_runtime
    [ "$status" -eq 0 ]
    printf '%s\n' 'RED_SENTINEL:runner-local-payload-binding'
}

@test "stop and online-idle mutants are killed behaviorally" {
    setup_provision_runtime
    local original="$BATS_TEST_TMPDIR/provisioner-runtime.original"
    cp "$PROVISIONER" "$original"
    python3 - "$PROVISIONER" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
old = '''        systemctl stop "$UNIT_NAME" 2>/dev/null || {
            disable_runner_service || \\
                echo "ERROR: trusted runner rollback could not prove fail-closed state" >&2
            echo "ERROR: unable to stop trusted runner service" >&2
            exit 1
        }
'''
new = '''        true
'''
assert source.count(old) == 1
path.write_text(source.replace(old, new, 1), encoding="utf-8")
PY
    TALO_MOCK_STOP_FAILURE=1 run_provision_runtime
    [ "$status" -eq 0 ]

    cp "$original" "$PROVISIONER"
    sed -i 's/($runner.busy == false)/(true)/' "$PROVISIONER"
    TALO_MOCK_RUNNERS_MODE=busy run_provision_runtime
    [ "$status" -eq 0 ]
    printf '%s\n' 'RED_SENTINEL:runner-runtime-terminal-state'
}

@test "preflight accepts only the exact upstream workflow and PR tuple" {
    local preflight="$ROOT/dev-tools/preflight-talo-0001-workflow-run.sh"
    local event="$BATS_TEST_TMPDIR/event.json"
    python3 - "$event" <<'PY'
import json
from pathlib import Path
import sys

head = "d1fa4f7ada7fc782b6055f4cacc41092848d1400"
payload = {"workflow_run": {
    "workflow_id": 270931528,
    "name": "dev-tools-lint",
    "path": ".github/workflows/dev-tools-lint.yml",
    "event": "pull_request",
    "conclusion": "success",
    "head_sha": head,
    "head_repository": {"full_name": "Arcanada-one/datarim"},
    "repository": {"full_name": "Arcanada-one/datarim"},
    "pull_requests": [{
        "number": 394,
        "head": {"sha": head, "ref": "research/TALO-0001-frontend-design", "repo": {"url": "https://api.github.com/repos/Arcanada-one/datarim"}},
        "base": {"ref": "main", "repo": {"url": "https://api.github.com/repos/Arcanada-one/datarim"}},
    }],
}}
Path(sys.argv[1]).write_text(json.dumps(payload), encoding="utf-8")
PY
    run "$preflight" "$event"
    [ "$status" -eq 0 ]

    while IFS='|' read -r expression value; do
        python3 - "$event" "$expression" "$value" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
target = data
parts = sys.argv[2].split(".")
for part in parts[:-1]:
    target = target[int(part)] if part.isdigit() else target[part]
target[parts[-1]] = json.loads(sys.argv[3])
path.write_text(json.dumps(data), encoding="utf-8")
PY
        run "$preflight" "$event"
        [ "$status" -ne 0 ]
        python3 - "$event" "$expression" <<'PY'
import json
from pathlib import Path
import sys

# Restore from the code-owned baseline by reversing the single hostile value.
defaults = {
    "workflow_run.workflow_id": 270931528,
    "workflow_run.name": "dev-tools-lint",
    "workflow_run.path": ".github/workflows/dev-tools-lint.yml",
    "workflow_run.event": "pull_request",
    "workflow_run.conclusion": "success",
    "workflow_run.head_repository.full_name": "Arcanada-one/datarim",
    "workflow_run.repository.full_name": "Arcanada-one/datarim",
    "workflow_run.pull_requests.0.head.sha": "d1fa4f7ada7fc782b6055f4cacc41092848d1400",
    "workflow_run.pull_requests.0.number": 394,
    "workflow_run.pull_requests.0.head.ref": "research/TALO-0001-frontend-design",
    "workflow_run.pull_requests.0.head.repo.url": "https://api.github.com/repos/Arcanada-one/datarim",
    "workflow_run.pull_requests.0.base.ref": "main",
    "workflow_run.pull_requests.0.base.repo.url": "https://api.github.com/repos/Arcanada-one/datarim",
}
path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
target = data
parts = sys.argv[2].split(".")
for part in parts[:-1]:
    target = target[int(part)] if part.isdigit() else target[part]
target[parts[-1]] = defaults[sys.argv[2]]
path.write_text(json.dumps(data), encoding="utf-8")
PY
    done <<'MUTANTS'
workflow_run.workflow_id|999
workflow_run.name|"other"
workflow_run.path|".github/workflows/other.yml"
workflow_run.event|"push"
workflow_run.conclusion|"failure"
workflow_run.head_repository.full_name|"attacker/fork"
workflow_run.repository.full_name|"attacker/fork"
workflow_run.pull_requests.0.head.sha|"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
workflow_run.pull_requests.0.number|999
workflow_run.pull_requests.0.head.ref|"attacker-branch"
workflow_run.pull_requests.0.head.repo.url|"https://api.github.com/repos/attacker/fork"
workflow_run.pull_requests.0.base.ref|"feature"
workflow_run.pull_requests.0.base.repo.url|"https://api.github.com/repos/attacker/fork"
MUTANTS
}
