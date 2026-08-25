#!/usr/bin/env bats
set -euo pipefail

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
        sudo chmod -R u+w "$RUNNER_FIXTURE"
        sudo chown -R "$(id -u):$(id -g)" "$RUNNER_FIXTURE"
    fi
}

make_runner_fixture_editable() {
    if [ -n "${RUNNER_FIXTURE:-}" ] \
        && [[ "$RUNNER_FIXTURE" == "$BATS_TEST_TMPDIR/"* ]] \
        && [ -e "$RUNNER_FIXTURE" ]; then
        sudo chmod -R u+w "$RUNNER_FIXTURE"
        sudo chown -R "$(id -u):$(id -g)" "$RUNNER_FIXTURE"
    fi
}

assert_file_lacks() {
    local pattern=$1 file=$2
    if grep -q -- "$pattern" "$file"; then
        printf 'unexpected pattern %s in %s\n' "$pattern" "$file" >&2
        return 1
    fi
}

reseal_registration_identity() {
    local runner_digest credentials_digest rsa_digest
    runner_digest=$(sha256sum "$RUNNER_FIXTURE/.runner")
    runner_digest=${runner_digest%% *}
    credentials_digest=$(sha256sum "$RUNNER_FIXTURE/.credentials")
    credentials_digest=${credentials_digest%% *}
    rsa_digest=$(sha256sum "$RUNNER_FIXTURE/.credentials_rsaparams")
    rsa_digest=${rsa_digest%% *}
    jq -n --arg runner "$runner_digest" \
        --arg credentials "$credentials_digest" --arg rsa "$rsa_digest" \
        '{schema_version:1,runner_id:7001,group_id:42,runner_sha256:$runner,credentials_sha256:$credentials,rsa_sha256:$rsa}' \
        >"$RUNNER_FIXTURE/.talo-registration-seal"
}

run_check() {
    run python3 "$FIXTURE/dev-tools/check-talo-0001-workflow-contract.py"
}

candidate_materializer_source() {
    sed -n '/^materialize_candidate_blob() {/,/^}/p' \
        "$FIXTURE/dev-tools/trusted-talo-0001-replay.sh"
}

workflow_step_run() {
    python3 - "$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml" "$1" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    workflow = yaml.safe_load(handle)
for job in workflow["jobs"].values():
    for step in job["steps"]:
        if step.get("name") == sys.argv[2]:
            print(step["run"])
            raise SystemExit(0)
raise SystemExit(1)
PY
}

setup_provision_runtime() {
    PROVISIONER="$FIXTURE/dev-tools/provision-talo-0001-trusted-runner.sh"
    MOCK_BIN="$BATS_TEST_TMPDIR/provision-mock-bin"
    MOCK_LOG="$BATS_TEST_TMPDIR/provision-commands.log"
    RUNNER_FIXTURE="$BATS_TEST_TMPDIR/runner"
    IDENTITY_FIXTURE="$BATS_TEST_TMPDIR/runner-identity"
    PROC_FIXTURE="$BATS_TEST_TMPDIR/proc"
    TEST_RUNNER_USER=$(id -un)
    TEST_RUNNER_UID=$(id -u)
    TEST_RUNNER_GID=$(id -g)
    make_runner_fixture_editable
    mkdir -p "$MOCK_BIN" "$RUNNER_FIXTURE/bin" "$RUNNER_FIXTURE/externals" \
        "$PROC_FIXTURE/4242"
    mkdir -p "$IDENTITY_FIXTURE"
    for command in chmod chown curl getent gh install pgrep sudo systemctl sleep; do
        ln -sf "$ROOT/dev-tools/tests/fixtures/talo-0001-command-mock.sh" \
            "$MOCK_BIN/$command"
    done
    sed -i "s#RUNNER_DIR=/srv/talo-0001-trusted/runner#RUNNER_DIR=$RUNNER_FIXTURE#" \
        "$PROVISIONER"
    sed -i "s#RUNNER_USER=talo-replay#RUNNER_USER=$TEST_RUNNER_USER#" \
        "$PROVISIONER"
    sed -i "s#PROC_ROOT=/proc#PROC_ROOT=$PROC_FIXTURE#" "$PROVISIONER"
    cat >"$RUNNER_FIXTURE/config.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'config.sh %s\n' "$*" >>"${TALO_MOCK_LOG:?}"
token=${ACTIONS_RUNNER_INPUT_TOKEN:?}
tr '\0' ' ' </proc/$$/cmdline >"${TALO_MOCK_CONFIG_CMDLINE:?}"
if grep -q -- "$token" "${TALO_MOCK_CONFIG_CMDLINE:?}"; then
    exit 97
fi
unset ACTIONS_RUNNER_INPUT_TOKEN
bash -c '[ -z "${ACTIONS_RUNNER_INPUT_TOKEN:-}" ]'
: >"${TALO_MOCK_CONFIG_ENV_REMOVED:?}"
cd "$(dirname "$0")"
if [ "${TALO_MOCK_REPLACE_EXEC:-0}" = 1 ]; then
    printf '%s\n' 'config-replace-attempt' >>"${TALO_MOCK_LOG:?}"
    printf '%s\n' '#!/usr/bin/env bash' 'printf stolen-token' >_diag/hostile-config.sh
    if mv _diag/hostile-config.sh "$0" 2>/dev/null; then
        exit 98
    fi
fi
if [ "${1:-}" = remove ]; then
    rm -f -- .runner .credentials .credentials_rsaparams .env .path
    exit 0
fi
: >"${TALO_MOCK_CONFIG_STARTED:?}"
[ "${TALO_MOCK_CONFIG_REMOTE_ONLY:-0}" != 1 ] || exit 1
cat >.runner <<'JSON'
{"AgentId":7001,"AgentName":"talo-0001-trusted-arcana-devs","PoolId":42,"PoolName":"talo-0001-trusted","DisableUpdate":true,"Ephemeral":false,"ServerUrl":"https://pipelinesghubeus26.actions.githubusercontent.com/AbCdEfGhIjKlMnOpQrStUvWxYz012345/","GitHubUrl":"https://github.com/Arcanada-one","WorkFolder":"_work","UseV2Flow":true,"UseRunnerAdminFlow":true,"ServerUrlV2":"https://broker.actions.githubusercontent.com/"}
JSON
cp -- "${TALO_MOCK_CREDENTIALS_TEMPLATE:?}" .credentials
cp -- "${TALO_MOCK_RSA_TEMPLATE:?}" .credentials_rsaparams
[ "${TALO_MOCK_CONFIG_FAILURE:-0}" != 1 ]
SH
    chmod +x "$RUNNER_FIXTURE/config.sh"
    printf '%s\n' fixture-run >"$RUNNER_FIXTURE/run.sh"
    printf '%s\n' fixture-listener >"$RUNNER_FIXTURE/bin/Runner.Listener"
    printf '%s\n' fixture-worker >"$RUNNER_FIXTURE/bin/Runner.Worker"
    printf '%s\n' fixture-support >"$RUNNER_FIXTURE/externals/support.bin"
    ln -sfn "$RUNNER_FIXTURE/bin/Runner.Listener" "$PROC_FIXTURE/4242/exe"
    printf 'Uid:\t%s\t%s\t%s\t%s\nGid:\t%s\t%s\t%s\t%s\n' \
        "$TEST_RUNNER_UID" "$TEST_RUNNER_UID" "$TEST_RUNNER_UID" \
        "$TEST_RUNNER_UID" "$TEST_RUNNER_GID" "$TEST_RUNNER_GID" \
        "$TEST_RUNNER_GID" "$TEST_RUNNER_GID" >"$PROC_FIXTURE/4242/status"
    printf '0::/system.slice/talo-0001-trusted-runner.service\n' \
        >"$PROC_FIXTURE/4242/cgroup"
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
    cat >"$IDENTITY_FIXTURE/.runner" <<'JSON'
{"AgentId":7001,"AgentName":"talo-0001-trusted-arcana-devs","PoolId":42,"PoolName":"talo-0001-trusted","DisableUpdate":true,"Ephemeral":false,"ServerUrl":"https://pipelinesghubeus26.actions.githubusercontent.com/AbCdEfGhIjKlMnOpQrStUvWxYz012345/","GitHubUrl":"https://github.com/Arcanada-one","WorkFolder":"_work","UseV2Flow":true,"UseRunnerAdminFlow":true,"ServerUrlV2":"https://broker.actions.githubusercontent.com/"}
JSON
    cat >"$IDENTITY_FIXTURE/.credentials" <<'JSON'
{"Scheme":"OAuth","Data":{"clientId":"11111111-2222-4333-8444-555555555555","authorizationUrl":"https://pipelinesghubeus26.actions.githubusercontent.com/AbCdEfGhIjKlMnOpQrStUvWxYz012345/","requireFipsCryptography":"False","enableAuthMigrationByDefault":"true","authorizationUrlV2":"https://broker.actions.githubusercontent.com/"}}
JSON
    python3 - "$IDENTITY_FIXTURE/.credentials_rsaparams" <<'PY'
import base64
import json
from pathlib import Path
import sys

lengths = {"d": 256, "dp": 128, "dq": 128, "inverseQ": 128,
           "modulus": 256, "p": 128, "q": 128}
payload = {key: base64.b64encode(bytes([index + 1]) * length).decode()
           for index, (key, length) in enumerate(lengths.items())}
payload["exponent"] = base64.b64encode(b"\x01\x00\x01").decode()
Path(sys.argv[1]).write_text(json.dumps(payload, separators=(",", ":")), encoding="utf-8")
PY
    cp -- "$IDENTITY_FIXTURE/.runner" "$RUNNER_FIXTURE/.runner"
    cp -- "$IDENTITY_FIXTURE/.credentials" "$RUNNER_FIXTURE/.credentials"
    cp -- "$IDENTITY_FIXTURE/.credentials_rsaparams" \
        "$RUNNER_FIXTURE/.credentials_rsaparams"
    reseal_registration_identity
    git -C "$FIXTURE" init -q
    git -C "$FIXTURE" config user.email test@example.com
    git -C "$FIXTURE" config user.name test
    git -C "$FIXTURE" add \
        .github/workflows/talo-0001-trusted-replay.yml \
        dev-tools/provision-talo-0001-trusted-runner.sh \
        dev-tools/systemd/talo-0001-trusted-runner.service
    git -C "$FIXTURE" commit --allow-empty -qm trusted-main
    MOCK_MAIN_COMMIT=$(git -C "$FIXTURE" rev-parse HEAD)
    MOCK_BLOB="$(git hash-object "$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml")"
    MOCK_UNIT_BLOB="$(git hash-object "$FIXTURE/dev-tools/systemd/talo-0001-trusted-runner.service")"
    MOCK_SERVICE_STATE="$BATS_TEST_TMPDIR/provision-service-state"
    MOCK_REGISTRATION_REMOVED="$BATS_TEST_TMPDIR/registration-removed"
    MOCK_DELETE_COUNTER="$BATS_TEST_TMPDIR/delete-counter"
    MOCK_CONFIG_STARTED="$BATS_TEST_TMPDIR/config-started"
    MOCK_CONFIG_CMDLINE="$BATS_TEST_TMPDIR/config-cmdline"
    MOCK_CONFIG_ENV_REMOVED="$BATS_TEST_TMPDIR/config-env-removed"
    MOCK_PGREP_COUNTER="$BATS_TEST_TMPDIR/pgrep-counter"
    MOCK_INSTALLED_UNIT="$BATS_TEST_TMPDIR/installed-talo-runner.service"
    : >"$MOCK_LOG"
    rm -f -- "$MOCK_REGISTRATION_REMOVED"
    rm -f -- "$MOCK_CONFIG_STARTED"
    printf '%s\n' 0 >"$MOCK_DELETE_COUNTER"
    printf '%s\n' 0 >"$MOCK_PGREP_COUNTER"
    printf '%s\n' enabled >"$MOCK_SERVICE_STATE"
}

prepare_fresh_runner_payload() {
    local archive_source="$BATS_TEST_TMPDIR/archive-source"
    MOCK_ARCHIVE="$BATS_TEST_TMPDIR/actions-runner.tar.gz"
    mkdir -p "$archive_source"
    cp -a "$RUNNER_FIXTURE/." "$archive_source/"
    rm -f -- "$archive_source/.runner" "$archive_source/.credentials" \
        "$archive_source/.credentials_rsaparams" \
        "$archive_source/.talo-registration-seal"
    tar -czf "$MOCK_ARCHIVE" -C "$archive_source" .
    archive_digest=$(sha256sum "$MOCK_ARCHIVE")
    archive_digest=${archive_digest%% *}
    sed -i -E \
        "s#^RUNNER_ARCHIVE_SHA256=[0-9a-f]{64}#RUNNER_ARCHIVE_SHA256=$archive_digest#" \
        "$PROVISIONER"
    rm -rf -- "$RUNNER_FIXTURE"
}

run_provision_runtime() {
    if [ -f "$RUNNER_FIXTURE/.runner" ]; then
        sudo chown -R root:root \
            "$RUNNER_FIXTURE/bin" "$RUNNER_FIXTURE/externals" \
            "$RUNNER_FIXTURE/config.sh" "$RUNNER_FIXTURE/env.sh" \
            "$RUNNER_FIXTURE/run.sh" \
            "$RUNNER_FIXTURE/run-helper.cmd.template" \
            "$RUNNER_FIXTURE/run-helper.sh.template" \
            "$RUNNER_FIXTURE/safe_sleep.sh"
        sudo chmod -R a-w \
            "$RUNNER_FIXTURE/bin" "$RUNNER_FIXTURE/externals" \
            "$RUNNER_FIXTURE/config.sh" "$RUNNER_FIXTURE/env.sh" \
            "$RUNNER_FIXTURE/run.sh" \
            "$RUNNER_FIXTURE/run-helper.cmd.template" \
            "$RUNNER_FIXTURE/run-helper.sh.template" \
            "$RUNNER_FIXTURE/safe_sleep.sh"
        sudo chown root:root "$RUNNER_FIXTURE"
        sudo chmod 0755 "$RUNNER_FIXTURE"
        sudo chmod g-s,o-t "$RUNNER_FIXTURE"
        for identity in .runner .credentials .credentials_rsaparams; do
            sudo chown "root:$TEST_RUNNER_GID" "$RUNNER_FIXTURE/$identity"
            sudo chmod 0640 "$RUNNER_FIXTURE/$identity"
        done
        sudo chown root:root "$RUNNER_FIXTURE/.talo-registration-seal"
        sudo chmod 0600 "$RUNNER_FIXTURE/.talo-registration-seal"
    fi
    if [ "${TALO_MOCK_PRESERVE_MAIN_COMMIT:-0}" != 1 ]; then
        git -C "$FIXTURE" add \
            .github/workflows/talo-0001-trusted-replay.yml \
            dev-tools/provision-talo-0001-trusted-runner.sh \
            dev-tools/systemd/talo-0001-trusted-runner.service
        git -C "$FIXTURE" commit --allow-empty -qm runtime-authority
        MOCK_MAIN_COMMIT=$(git -C "$FIXTURE" rev-parse HEAD)
    fi
    MOCK_PROVISIONER_BLOB="${TALO_MOCK_PROVISIONER_BLOB_OVERRIDE:-$(git hash-object "$PROVISIONER")}"
    run sudo env "PATH=$MOCK_BIN:$PATH" \
        "TALO_MOCK_LOG=$MOCK_LOG" \
        "TALO_MOCK_GH_MODE=${TALO_MOCK_GH_MODE:-success}" \
        "TALO_MOCK_BLOB=$MOCK_BLOB" \
        "TALO_MOCK_MAIN_COMMIT=$MOCK_MAIN_COMMIT" \
        "TALO_MOCK_ADVANCED_MAIN_COMMIT=${TALO_MOCK_ADVANCED_MAIN_COMMIT:-}" \
        "TALO_MOCK_MAIN_SEQUENCE=${TALO_MOCK_MAIN_SEQUENCE:-stable}" \
        "TALO_MOCK_MAIN_COUNTER=$BATS_TEST_TMPDIR/main-ref-counter" \
        "TALO_MOCK_PROVISIONER_BLOB=$MOCK_PROVISIONER_BLOB" \
        "TALO_MOCK_UNIT_BLOB=$MOCK_UNIT_BLOB" \
        "TALO_MOCK_RUNNERS_MODE=${TALO_MOCK_RUNNERS_MODE:-one}" \
        "TALO_MOCK_STOP_FAILURE=${TALO_MOCK_STOP_FAILURE:-0}" \
        "TALO_MOCK_ENABLE_FAILURE=${TALO_MOCK_ENABLE_FAILURE:-0}" \
        "TALO_MOCK_CONFIG_FAILURE=${TALO_MOCK_CONFIG_FAILURE:-0}" \
        "TALO_MOCK_CONFIG_REMOTE_ONLY=${TALO_MOCK_CONFIG_REMOTE_ONLY:-0}" \
        "TALO_MOCK_GROUP_MUTATION_FAILURE=${TALO_MOCK_GROUP_MUTATION_FAILURE:-0}" \
        "TALO_MOCK_DELETE_FAILURES=${TALO_MOCK_DELETE_FAILURES:-0}" \
        "TALO_MOCK_ENFORCE_TRAVERSAL=${TALO_MOCK_ENFORCE_TRAVERSAL:-0}" \
        "TALO_MOCK_RUNNER_PROCESS=${TALO_MOCK_RUNNER_PROCESS:-0}" \
        "TALO_MOCK_PGREP_COUNTER=$MOCK_PGREP_COUNTER" \
        "TALO_MOCK_REPLACE_EXEC=${TALO_MOCK_REPLACE_EXEC:-0}" \
        "TALO_MOCK_REAL_UID=${TALO_MOCK_REAL_UID:-0}" \
        "TALO_MOCK_RUNNER_USER=$TEST_RUNNER_USER" \
        "TALO_MOCK_RUNNER_UID=$TEST_RUNNER_UID" \
        "TALO_MOCK_RUNNER_GID=$TEST_RUNNER_GID" \
        "TALO_MOCK_ARCHIVE=${MOCK_ARCHIVE:-}" \
        "TALO_MOCK_RUNNER_DIR=$RUNNER_FIXTURE" \
        "TALO_MOCK_SERVICE_STATE=$MOCK_SERVICE_STATE" \
        "TALO_MOCK_REGISTRATION_REMOVED=$MOCK_REGISTRATION_REMOVED" \
        "TALO_MOCK_DELETE_COUNTER=$MOCK_DELETE_COUNTER" \
        "TALO_MOCK_CONFIG_STARTED=$MOCK_CONFIG_STARTED" \
        "TALO_MOCK_CONFIG_CMDLINE=$MOCK_CONFIG_CMDLINE" \
        "TALO_MOCK_CONFIG_ENV_REMOVED=$MOCK_CONFIG_ENV_REMOVED" \
        "TALO_MOCK_INSTALLED_UNIT=$MOCK_INSTALLED_UNIT" \
        "TALO_MOCK_MUTABLE_UNIT=$FIXTURE/dev-tools/systemd/talo-0001-trusted-runner.service" \
        "TALO_MOCK_SWAP_UNIT_SOURCE=${TALO_MOCK_SWAP_UNIT_SOURCE:-}" \
        "TALO_MOCK_CREDENTIALS_TEMPLATE=$IDENTITY_FIXTURE/.credentials" \
        "TALO_MOCK_RSA_TEMPLATE=$IDENTITY_FIXTURE/.credentials_rsaparams" \
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
        && [[ "$output" == *'mismatch:trusted-replay-job'* ]]
}

@test "trusted workflow has no unused pull-request permission" {
    local trusted="$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml"
    run grep -q 'pull-requests:' "$trusted"
    [ "$status" -ne 0 ]
    sed -i 's/permissions: {}/permissions:\n  pull-requests: read/' "$trusted"
    run_check
    [ "$status" -eq 1 ] && [[ "$output" == *'mismatch:trusted-permissions'* ]]
}

@test "trusted replay requires the exact workflow-scoped runner group" {
    local workflow="$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml"
    local original="$BATS_TEST_TMPDIR/trusted-group.original"
    cp "$workflow" "$original"

    sed -i '/      group: talo-0001-trusted/d' "$workflow"
    run_check
    [ "$status" -eq 1 ] && [[ "$output" == *'mismatch:trusted-replay-job'* ]]

    cp "$original" "$workflow"
    sed -i 's/group: talo-0001-trusted/group: Default/' "$workflow"
    run_check
    [ "$status" -eq 1 ] && [[ "$output" == *'mismatch:trusted-replay-job'* ]]
}

@test "hosted initializer owns the current check before trusted runner queue" {
    local workflow="$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml"
    local original="$BATS_TEST_TMPDIR/hosted-initializer.original"
    run python3 - "$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as handle:
    workflow = yaml.safe_load(handle)
assert set(workflow["jobs"]) == {"initialize", "replay"}
initializer = workflow["jobs"]["initialize"]
replay = workflow["jobs"]["replay"]
assert initializer["runs-on"] == "ubuntu-latest"
assert initializer["permissions"] == {"checks": "write", "contents": "read"}
assert len(initializer["steps"]) == 1
assert all("uses" not in step for step in initializer["steps"])
step = initializer["steps"][0]
assert set(step["env"]) == {
    "GH_TOKEN", "HEAD_SHA", "BASE_SHA", "TRUSTED_RUN_ID",
    "TRUSTED_RUN_ATTEMPT", "EVENT_WORKFLOW_SHA", "SOURCE_RUN_ID",
    "SOURCE_RUN_ATTEMPT",
}
assert step["env"]["GH_TOKEN"] == "${{ github.token }}"
assert all(token not in step["run"] for token in (
    "secrets.", "candidate", "docker ", "curl ", "actions/checkout",
))
assert replay["needs"] == ["initialize"]
assert replay["runs-on"]["group"] == "talo-0001-trusted"
assert "needs.initialize.result == 'success'" in replay["if"]
assert "needs.initialize.outputs.current_base == 'true'" in replay["if"]
PY
    [ "$status" -eq 0 ]

    cp "$workflow" "$original"
    sed -i '0,/runs-on: ubuntu-latest/{s/runs-on: ubuntu-latest/runs-on: [self-hosted, talo-0001-trusted]/}' \
        "$workflow"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *'mismatch:trusted-initializer-job'* ]]

    cp "$original" "$workflow"
    sed -i 's/needs: \[initialize\]/needs: []/' "$workflow"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *'mismatch:trusted-replay-job'* ]]
}

@test "hosted live-main API authority is exact and least-privileged" {
    local workflow="$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml"
    local original="$BATS_TEST_TMPDIR/live-main-auth.original"
    cp "$workflow" "$original"

    sed -i '/      contents: read/d' "$workflow"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'mismatch:trusted-initializer-job'* ]]

    cp "$original" "$workflow"
    sed -i '0,/GH_TOKEN: \${{ github.token }}/{s/GH_TOKEN: \${{ github.token }}/GH_TOKEN: disabled/}' \
        "$workflow"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'mismatch:trusted-initializer-job'* ]]

    cp "$original" "$workflow"
    sed -i 's#git/ref/heads/main#git/ref/heads/retired#' "$workflow"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'mismatch:trusted-initializer-job'* ]]
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
text = text.replace("      checks: write", "      checks: write\n      contents: write", 1)
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

@test "candidate materializer rejects a committed symlink before reading its target" {
    local repository="$BATS_TEST_TMPDIR/symlink-candidate"
    local materialized="$BATS_TEST_TMPDIR/symlink-materialized"
    mkdir -p "$repository/datarim/insights" "$materialized"
    git -C "$repository" init -q
    git -C "$repository" config user.email test@example.com
    git -C "$repository" config user.name test
    ln -s /etc/hostname \
        "$repository/datarim/insights/TALO-0001-research-authority-audit.json"
    git -C "$repository" add .
    git -C "$repository" commit -qm symlink
    local head_sha source
    head_sha=$(git -C "$repository" rev-parse HEAD)
    source=$(candidate_materializer_source)
    run env CANDIDATE="$repository" candidate_materialized="$materialized" \
        head_sha="$head_sha" bash -c "$source
materialize_candidate_blob datarim/insights/TALO-0001-research-authority-audit.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *'candidate object is not an exact regular Git blob'* ]]
    [ ! -e "$materialized/datarim/insights/TALO-0001-research-authority-audit.json" ]
}

@test "candidate materializer ignores replacement refs for every blob read" {
    local repository="$BATS_TEST_TMPDIR/replaced-candidate"
    local materialized="$BATS_TEST_TMPDIR/replaced-materialized"
    mkdir -p "$repository/dev-tools" "$materialized"
    git -C "$repository" init -q
    git -C "$repository" config user.email test@example.com
    git -C "$repository" config user.name test
    printf '%s' original-validator >"$repository/dev-tools/check-research-authority-audit.py"
    git -C "$repository" add .
    git -C "$repository" commit -qm original
    local head_sha original_object hostile_object expected source mutant
    head_sha=$(git -C "$repository" rev-parse HEAD)
    original_object=$(git -C "$repository" rev-parse \
        "$head_sha:dev-tools/check-research-authority-audit.py")
    printf '%s' hostile-validator >"$BATS_TEST_TMPDIR/hostile-validator"
    hostile_object=$(git -C "$repository" hash-object -w \
        "$BATS_TEST_TMPDIR/hostile-validator")
    git -C "$repository" replace "$original_object" "$hostile_object"
    expected=$(printf '%s' original-validator | sha256sum | cut -d' ' -f1)
    source=$(candidate_materializer_source)
    run env CANDIDATE="$repository" candidate_materialized="$materialized" \
        head_sha="$head_sha" bash -c "$source
materialize_candidate_blob dev-tools/check-research-authority-audit.py"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
    [ "$(cat "$materialized/dev-tools/check-research-authority-audit.py")" = original-validator ]

    mutant=${source//GIT_NO_REPLACE_OBJECTS=1 /}
    run env CANDIDATE="$repository" \
        candidate_materialized="$BATS_TEST_TMPDIR/replaced-mutant" \
        head_sha="$head_sha" bash -c "mkdir -p \"\$candidate_materialized\"
$mutant
materialize_candidate_blob dev-tools/check-research-authority-audit.py"
    [ "$status" -eq 0 ]
    [ "$output" != "$expected" ]
    printf '%s\n' 'RED_SENTINEL:candidate-replacement-ref-guard'
}

@test "Git-object modes guards and public object digests are load-bearing" {
    local controller="$FIXTURE/dev-tools/trusted-talo-0001-replay.sh"
    local publisher="$FIXTURE/dev-tools/publish-talo-0001-check.sh"
    local original="$BATS_TEST_TMPDIR/object-controller.original"
    cp "$controller" "$original"
    sed -i 's/\[ "$mode" != 100644 \]/[ "$mode" != 120000 ]/' "$controller"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *'missing:candidate-object-contract:'* ]]

    cp "$original" "$controller"
    sed -i 's/GIT_NO_REPLACE_OBJECTS=1 git -C "$CANDIDATE" cat-file/git -C "$CANDIDATE" cat-file/g' \
        "$controller"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *'missing:candidate-object-contract:'* ]]

    cp "$original" "$controller"
    sed -i 's/candidate_validator_object_sha256/candidate_validator_sha256/g' \
        "$controller" "$publisher"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *'missing:candidate-object-contract:'* ]]
    [[ "$output" == *'forbidden:worktree-candidate-digest-field'* ]]
}

@test "early replay failure invalidates a stale MET attestation first" {
    local controller="$FIXTURE/dev-tools/trusted-talo-0001-replay.sh"
    local event="$BATS_TEST_TMPDIR/invalid-event.json"
    local attestation_path="$BATS_TEST_TMPDIR/stale-attestation.json"
    printf '%s\n' '{}' >"$event"
    printf '%s\n' '{"verdict":"MET","head_sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}' \
        >"$attestation_path"
    run env TALO_TRUSTED_RUN_ID=9001 TALO_TRUSTED_RUN_ATTEMPT=1 \
        TALO_TRUSTED_WORKFLOW_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        TALO_SOURCE_RUN_ID=8001 TALO_SOURCE_RUN_ATTEMPT=1 \
        TALO_BASE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        TALO_EXECUTION_NONCE=0000000000000000000000000000000000000000000000000000000000000000 \
        "$controller" --event "$event" \
        --candidate "$BATS_TEST_TMPDIR/candidate" --output "$attestation_path"
    [ "$status" -ne 0 ]
    [ ! -s "$attestation_path" ]
    [ "$(stat -c '%a' "$attestation_path")" = 600 ]
}

@test "trusted execution revalidates live main before privileged collection" {
    local controller="$FIXTURE/dev-tools/trusted-talo-0001-replay.sh"
    local event="$BATS_TEST_TMPDIR/advanced-main-event.json"
    local attestation_path="$BATS_TEST_TMPDIR/advanced-main-attestation.json"
    local mock_bin="$BATS_TEST_TMPDIR/advanced-main-controller-bin"
    local log="$BATS_TEST_TMPDIR/advanced-main-controller.log"
    local trusted=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local advanced=2222222222222222222222222222222222222222
    mkdir -p "$mock_bin"
    printf '%s\n' '{}' >"$event"
    cat >"$mock_bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TALO_LIVE_REF_LOG:?}"
if [[ "$*" == *"repos/Arcanada-one/datarim/git/ref/heads/main"* ]]; then
    jq -cn --arg sha "${TALO_LIVE_MAIN:?}" \
        '{ref:"refs/heads/main",node_id:"REF_node",url:"https://api.github.com/repos/Arcanada-one/datarim/git/refs/heads/main",object:{sha:$sha,type:"commit",url:("https://api.github.com/repos/Arcanada-one/datarim/git/commits/" + $sha)}}'
fi
SH
    chmod +x "$mock_bin/gh"
    run env "PATH=$mock_bin:$PATH" TALO_LIVE_REF_LOG="$log" \
        TALO_LIVE_MAIN="$advanced" TALO_TRUSTED_RUN_ID=9010 \
        TALO_TRUSTED_RUN_ATTEMPT=1 TALO_TRUSTED_WORKFLOW_SHA="$trusted" \
        TALO_SOURCE_RUN_ID=8010 TALO_SOURCE_RUN_ATTEMPT=1 \
        TALO_BASE_SHA="$trusted" \
        TALO_EXECUTION_NONCE=0000000000000000000000000000000000000000000000000000000000000000 \
        "$controller" --event "$event" \
        --candidate "$BATS_TEST_TMPDIR/advanced-candidate" \
        --output "$attestation_path"
    [ "$status" -eq 1 ] \
        && grep -q 'git/ref/heads/main' "$log" \
        && [[ "$output" == *'trusted controller is no longer live main'* ]] \
        && [ ! -s "$attestation_path" ]
}

@test "trusted execution rejects main advance at its second live-ref callsite" {
    local controller="$FIXTURE/dev-tools/trusted-talo-0001-replay.sh"
    local event="$BATS_TEST_TMPDIR/two-read-event.json"
    local attestation_path="$BATS_TEST_TMPDIR/two-read-attestation.json"
    local candidate="$BATS_TEST_TMPDIR/two-read-candidate"
    local knowledge="$BATS_TEST_TMPDIR/two-read-knowledge"
    local mock_bin="$BATS_TEST_TMPDIR/two-read-bin"
    local log="$BATS_TEST_TMPDIR/two-read.log"
    local counter="$BATS_TEST_TMPDIR/two-read-counter"
    local trusted advanced=2222222222222222222222222222222222222222
    local snapshot head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb nonce
    git -C "$FIXTURE" init -q
    git -C "$FIXTURE" config user.email test@example.com
    git -C "$FIXTURE" config user.name test
    git -C "$FIXTURE" add .
    git -C "$FIXTURE" commit -qm controller
    trusted=$(git -C "$FIXTURE" rev-parse HEAD)
    git init -q "$knowledge"
    git -C "$knowledge" config user.email test@example.com
    git -C "$knowledge" config user.name test
    git -C "$knowledge" commit --allow-empty -qm snapshot
    snapshot=$(git -C "$knowledge" rev-parse HEAD)
    sed -i "s#^SNAPSHOT=.*#SNAPSHOT=$snapshot#; s#^KNOWLEDGE_ROOT=.*#KNOWLEDGE_ROOT=$knowledge#" \
        "$controller"
    git -C "$FIXTURE" add dev-tools/trusted-talo-0001-replay.sh
    git -C "$FIXTURE" commit -qm test-seam
    trusted=$(git -C "$FIXTURE" rev-parse HEAD)
    python3 - "$event" "$head" "$trusted" <<'PY'
import json
from pathlib import Path
import sys

head, base = sys.argv[2:]
payload = {"workflow_run": {
    "id": 8011, "run_attempt": 1, "workflow_id": 270931528,
    "name": "dev-tools-lint", "path": ".github/workflows/dev-tools-lint.yml",
    "event": "pull_request", "conclusion": "success", "head_sha": head,
    "head_repository": {"full_name": "Arcanada-one/datarim"},
    "repository": {"full_name": "Arcanada-one/datarim"},
    "pull_requests": [{"number": 394,
        "head": {"sha": head, "ref": "research/TALO-0001-frontend-design",
                 "repo": {"url": "https://api.github.com/repos/Arcanada-one/datarim"}},
        "base": {"ref": "main", "sha": base,
                 "repo": {"url": "https://api.github.com/repos/Arcanada-one/datarim"}}}]}}
Path(sys.argv[1]).write_text(json.dumps(payload), encoding="utf-8")
PY
    mkdir -p "$mock_bin"
    cat >"$mock_bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TALO_LIVE_REF_LOG:?}"
count=0
[ ! -f "${TALO_LIVE_REF_COUNTER:?}" ] || count=$(cat "$TALO_LIVE_REF_COUNTER")
count=$((count + 1))
printf '%s\n' "$count" >"$TALO_LIVE_REF_COUNTER"
sha=$TALO_TRUSTED_WORKFLOW_SHA
[ "$count" -lt 2 ] || sha=$TALO_ADVANCED_MAIN
jq -cn --arg sha "$sha" \
    '{ref:"refs/heads/main",node_id:"REF_node",url:"https://api.github.com/repos/Arcanada-one/datarim/git/refs/heads/main",object:{sha:$sha,type:"commit",url:("https://api.github.com/repos/Arcanada-one/datarim/git/commits/" + $sha)}}'
SH
    cat >"$mock_bin/git" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = init ] && [ "${2:-}" = --quiet ] \
    && [ "${3:-}" = "${TALO_CANDIDATE:?}" ]; then
    : >"${TALO_CANDIDATE_INIT_MARKER:?}"
    exit 89
fi
exec /usr/bin/git "$@"
SH
    chmod +x "$mock_bin/gh"
    chmod +x "$mock_bin/git"
    nonce=$(printf 'trusted_run_id=%s\ntrusted_run_attempt=%s\nworkflow_sha=%s\nsource_run_id=%s\nsource_run_attempt=%s\nhead_sha=%s\nbase_sha=%s\n' \
        9011 1 "$trusted" 8011 1 "$head" "$trusted" | sha256sum | cut -d' ' -f1)
    run env "PATH=$mock_bin:$PATH" TALO_LIVE_REF_LOG="$log" \
        TALO_LIVE_REF_COUNTER="$counter" TALO_ADVANCED_MAIN="$advanced" \
        TALO_CANDIDATE="$candidate" \
        TALO_CANDIDATE_INIT_MARKER="$BATS_TEST_TMPDIR/candidate-init-marker" \
        TALO_TRUSTED_RUN_ID=9011 TALO_TRUSTED_RUN_ATTEMPT=1 \
        TALO_TRUSTED_WORKFLOW_SHA="$trusted" TALO_SOURCE_RUN_ID=8011 \
        TALO_SOURCE_RUN_ATTEMPT=1 TALO_BASE_SHA="$trusted" \
        TALO_EXECUTION_NONCE="$nonce" "$controller" --event "$event" \
        --candidate "$candidate" --output "$attestation_path"
    [ "$status" -eq 1 ] \
        && [ "$(grep -c 'git/ref/heads/main' "$log")" -eq 2 ] \
        && [[ "$output" == *'trusted controller is no longer live main'* ]] \
        && [ ! -e "$candidate/.git" ] \
        && [ ! -s "$attestation_path" ]

    python3 - "$controller" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
needle = "require_live_main || exit 1"
position = source.rfind(needle)
assert position >= 0
path.write_text(source[:position] + ": # MUTANT removed second live-main call" +
                source[position + len(needle):], encoding="utf-8")
PY
    rm -f -- "$counter" "$BATS_TEST_TMPDIR/candidate-init-marker"
    : >"$log"
    run env "PATH=$mock_bin:$PATH" TALO_LIVE_REF_LOG="$log" \
        TALO_LIVE_REF_COUNTER="$counter" TALO_ADVANCED_MAIN="$advanced" \
        TALO_CANDIDATE="$candidate" \
        TALO_CANDIDATE_INIT_MARKER="$BATS_TEST_TMPDIR/candidate-init-marker" \
        TALO_TRUSTED_RUN_ID=9011 TALO_TRUSTED_RUN_ATTEMPT=1 \
        TALO_TRUSTED_WORKFLOW_SHA="$trusted" TALO_SOURCE_RUN_ID=8011 \
        TALO_SOURCE_RUN_ATTEMPT=1 TALO_BASE_SHA="$trusted" \
        TALO_EXECUTION_NONCE="$nonce" "$controller" --event "$event" \
        --candidate "$candidate" --output "$attestation_path"
    [ -e "$BATS_TEST_TMPDIR/candidate-init-marker" ]
    printf '%s\n' 'RED_SENTINEL:second-live-main-execution-callsite'
}

@test "publisher rejects a prior-run MET for the same candidate head" {
    local publisher="$FIXTURE/dev-tools/publish-talo-0001-check.sh"
    local attestation="$BATS_TEST_TMPDIR/prior-run-attestation.json"
    local mock_bin="$BATS_TEST_TMPDIR/publisher-bin"
    local log="$BATS_TEST_TMPDIR/publisher.log"
    local head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    local controller=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local base=$controller
    local nonce current_nonce advanced=2222222222222222222222222222222222222222
    mkdir -p "$mock_bin"
    cat >"$mock_bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TALO_PUBLISH_LOG:?}"
if [[ "$*" == *"repos/Arcanada-one/datarim/git/ref/heads/main"* ]]; then
    jq -cn --arg sha "${TALO_LIVE_MAIN:?}" \
        '{ref:"refs/heads/main",node_id:"REF_node",url:"https://api.github.com/repos/Arcanada-one/datarim/git/refs/heads/main",object:{sha:$sha,type:"commit",url:("https://api.github.com/repos/Arcanada-one/datarim/git/commits/" + $sha)}}'
elif [[ " $* " != *" --method "* ]] && [[ "$*" == *"check-runs/"* ]]; then
    jq -cn --argjson id "${TALO_PUBLISH_CHECK_ID:?}" \
        --arg head "${TALO_PUBLISH_HEAD:?}" \
        --arg nonce "${TALO_PUBLISH_NONCE:?}" \
        '{id:$id,name:"talo-0001-privileged-replay",head_sha:$head,external_id:$nonce,status:"in_progress"}'
fi
SH
    chmod +x "$mock_bin/gh"
    nonce=$(printf 'trusted_run_id=%s\ntrusted_run_attempt=%s\nworkflow_sha=%s\nsource_run_id=%s\nsource_run_attempt=%s\nhead_sha=%s\nbase_sha=%s\n' \
        9000 1 "$controller" 8001 1 "$head" "$base" | sha256sum | cut -d' ' -f1)
    current_nonce=$(printf 'trusted_run_id=%s\ntrusted_run_attempt=%s\nworkflow_sha=%s\nsource_run_id=%s\nsource_run_attempt=%s\nhead_sha=%s\nbase_sha=%s\n' \
        9001 1 "$controller" 8001 1 "$head" "$base" | sha256sum | cut -d' ' -f1)
    jq -n --arg head "$head" --arg base "$base" --arg controller "$controller" \
        --arg nonce "$nonce" \
        '{schema_version:1,verdict:"MET",head_sha:$head,base_sha:$base,controller_commit:$controller,trusted_run_id:9000,trusted_run_attempt:1,source_run_id:8001,source_run_attempt:1,execution_nonce_sha256:$nonce,knowledge_snapshot:"c636fea7b7dda0245fbbfd1da8a5a78c7e56c2ae",trusted_evaluator_sha256:"a0e86fc87493231afffd3164587f0c14e463f5e8c4acd8f4f9679e2504280d1a",candidate_validator_object_sha256:("1"*64),manifest_object_sha256:("2"*64),mutation_set_sha256:("3"*64),counts:{items:66,candidates:19,external_pins:8,derived_records:3,comments:2,mutants:7}}' \
        >"$attestation"
    chmod 0600 "$attestation"
    run env "PATH=$mock_bin:$PATH" TALO_PUBLISH_LOG="$log" \
        TALO_LIVE_MAIN="$controller" \
        TALO_PUBLISH_CHECK_ID=321 TALO_PUBLISH_HEAD="$head" \
        TALO_PUBLISH_NONCE="$current_nonce" CHECK_RUN_ID=321 \
        EXPECTED_EXECUTION_NONCE="$current_nonce" \
        ATTESTATION="$attestation" HEAD_SHA="$head" BASE_SHA="$base" \
        TRUSTED_RUN_ID=9001 TRUSTED_RUN_ATTEMPT=1 \
        TRUSTED_WORKFLOW_SHA="$controller" SOURCE_RUN_ID=8001 \
        SOURCE_RUN_ATTEMPT=1 "$publisher"
    [ "$status" -ne 0 ]
    grep -q 'conclusion=failure' "$log"
    assert_file_lacks 'conclusion=success' "$log"

    nonce=$current_nonce
    jq --arg nonce "$nonce" '.trusted_run_id = 9001 | .execution_nonce_sha256 = $nonce' \
        "$attestation" >"$attestation.next"
    mv "$attestation.next" "$attestation"
    chmod 0600 "$attestation"
    : >"$log"
    run env "PATH=$mock_bin:$PATH" TALO_PUBLISH_LOG="$log" \
        TALO_LIVE_MAIN="$controller" \
        TALO_PUBLISH_CHECK_ID=321 TALO_PUBLISH_HEAD="$head" \
        TALO_PUBLISH_NONCE="$nonce" CHECK_RUN_ID=321 \
        EXPECTED_EXECUTION_NONCE="$nonce" \
        ATTESTATION="$attestation" HEAD_SHA="$head" BASE_SHA="$base" \
        TRUSTED_RUN_ID=9001 TRUSTED_RUN_ATTEMPT=1 \
        TRUSTED_WORKFLOW_SHA="$controller" SOURCE_RUN_ID=8001 \
        SOURCE_RUN_ATTEMPT=1 "$publisher"
    [ "$status" -eq 0 ]
    grep -q 'conclusion=success' "$log"

    : >"$log"
    run env "PATH=$mock_bin:$PATH" TALO_PUBLISH_LOG="$log" \
        TALO_LIVE_MAIN="$advanced" \
        TALO_PUBLISH_CHECK_ID=321 TALO_PUBLISH_HEAD="$head" \
        TALO_PUBLISH_NONCE="$nonce" CHECK_RUN_ID=321 \
        EXPECTED_EXECUTION_NONCE="$nonce" \
        ATTESTATION="$attestation" HEAD_SHA="$head" BASE_SHA="$base" \
        TRUSTED_RUN_ID=9001 TRUSTED_RUN_ATTEMPT=1 \
        TRUSTED_WORKFLOW_SHA="$controller" SOURCE_RUN_ID=8001 \
        SOURCE_RUN_ATTEMPT=1 "$publisher"
    [ "$status" -eq 1 ] \
        && grep -q 'git/ref/heads/main' "$log" \
        && grep -q 'conclusion=failure' "$log" \
        && assert_file_lacks 'conclusion=success' "$log"

    local publisher_mutant="$BATS_TEST_TMPDIR/publisher-no-final-live-main.sh"
    cp "$publisher" "$publisher_mutant"
    python3 - "$publisher_mutant" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
needle = '''if [ "$conclusion" = success ]; then
    current_main=$(live_main_commit || true)
    if [ "$current_main" != "$TRUSTED_WORKFLOW_SHA" ]; then
        conclusion=failure
        summary='Trusted controller is no longer verified live main.'
    fi
fi
'''
assert source.count(needle) == 1
path.write_text(source.replace(needle, ": # MUTANT removed final live-main callsite\n"),
                encoding="utf-8")
PY
    chmod +x "$publisher_mutant"
    : >"$log"
    run env "PATH=$mock_bin:$PATH" TALO_PUBLISH_LOG="$log" \
        TALO_LIVE_MAIN="$advanced" \
        TALO_PUBLISH_CHECK_ID=321 TALO_PUBLISH_HEAD="$head" \
        TALO_PUBLISH_NONCE="$nonce" CHECK_RUN_ID=321 \
        EXPECTED_EXECUTION_NONCE="$nonce" \
        ATTESTATION="$attestation" HEAD_SHA="$head" BASE_SHA="$base" \
        TRUSTED_RUN_ID=9001 TRUSTED_RUN_ATTEMPT=1 \
        TRUSTED_WORKFLOW_SHA="$controller" SOURCE_RUN_ID=8001 \
        SOURCE_RUN_ATTEMPT=1 "$publisher_mutant"
    [ "$status" -eq 0 ] && grep -q 'conclusion=success' "$log"
    printf '%s\n' 'RED_SENTINEL:final-live-main-publisher-callsite'
}

@test "hosted pending survives an offline trusted queue and checkout failure terminalizes it" {
    local initializer fallback mock_bin log github_output nonce
    local head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    local controller=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local base=$controller
    initializer=$(workflow_step_run "Initialize checkout-independent current-run verdict")
    fallback=$(workflow_step_run "Publish fixed candidate-head verdict")
    mock_bin="$BATS_TEST_TMPDIR/checkout-failure-bin"
    log="$BATS_TEST_TMPDIR/checkout-failure.log"
    github_output="$BATS_TEST_TMPDIR/github-output"
    mkdir -p "$mock_bin"
    cat >"$mock_bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TALO_PUBLISH_LOG:?}"
if [[ "$*" == "api repos/Arcanada-one/datarim/git/ref/heads/main" ]]; then
    jq -cn --arg sha "${TALO_LIVE_MAIN:?}" \
        '{ref:"refs/heads/main",node_id:"REF_node",url:"https://api.github.com/repos/Arcanada-one/datarim/git/refs/heads/main",object:{sha:$sha,type:"commit",url:("https://api.github.com/repos/Arcanada-one/datarim/git/commits/" + $sha)}}'
elif [[ " $* " == *" --method POST "* ]]; then
    jq -cn --argjson id 321 --arg head "${TALO_PUBLISH_HEAD:?}" \
        --arg nonce "${TALO_PUBLISH_NONCE:?}" \
        '{id:$id,name:"talo-0001-privileged-replay",head_sha:$head,external_id:$nonce,status:"in_progress"}'
elif [[ " $* " != *" --method "* ]] && [[ "$*" == *"check-runs/321"* ]]; then
    jq -cn --argjson id 321 --arg head "${TALO_PUBLISH_HEAD:?}" \
        --arg nonce "${TALO_PUBLISH_NONCE:?}" \
        '{id:$id,name:"talo-0001-privileged-replay",head_sha:$head,external_id:$nonce,status:"in_progress"}'
fi
SH
    chmod +x "$mock_bin/gh"
    nonce=$(printf 'trusted_run_id=%s\ntrusted_run_attempt=%s\nworkflow_sha=%s\nsource_run_id=%s\nsource_run_attempt=%s\nhead_sha=%s\nbase_sha=%s\n' \
        9001 2 "$controller" 8001 3 "$head" "$base" | sha256sum | cut -d' ' -f1)
    run env "PATH=$mock_bin:$PATH" TALO_PUBLISH_LOG="$log" \
        TALO_PUBLISH_HEAD="$head" TALO_PUBLISH_NONCE="$nonce" \
        GITHUB_OUTPUT="$github_output" HEAD_SHA="$head" BASE_SHA="$base" \
        TRUSTED_RUN_ID=9001 TRUSTED_RUN_ATTEMPT=2 \
        TALO_LIVE_MAIN="$controller" EVENT_WORKFLOW_SHA="$controller" SOURCE_RUN_ID=8001 \
        SOURCE_RUN_ATTEMPT=3 bash -c "$initializer"
    [ "$status" -eq 0 ]
    grep -qx 'check_id=321' "$github_output"
    grep -qx "execution_nonce=$nonce" "$github_output"
    grep -qx 'current_base=true' "$github_output"
    grep -qx "head_sha=$head" "$github_output"
    grep -qx "base_sha=$base" "$github_output"
    grep -qx 'trusted_run_id=9001' "$github_output"
    grep -qx 'trusted_run_attempt=2' "$github_output"
    grep -qx "workflow_sha=$controller" "$github_output"
    grep -qx 'source_run_id=8001' "$github_output"
    grep -qx 'source_run_attempt=3' "$github_output"
    grep -q 'status=in_progress' "$log"
    grep -q "external_id=$nonce" "$log"

    : >"$log"
    run env "PATH=$mock_bin:$PATH" TALO_PUBLISH_LOG="$log" \
        TALO_PUBLISH_HEAD="$head" TALO_PUBLISH_NONCE="$nonce" \
        HEAD_SHA="$head" BASE_SHA="$base" CHECK_RUN_ID=321 \
        EXPECTED_EXECUTION_NONCE="$nonce" \
        TRUSTED_RUN_ID=9001 TRUSTED_RUN_ATTEMPT=2 \
        TRUSTED_WORKFLOW_SHA="$controller" SOURCE_RUN_ID=8001 \
        SOURCE_RUN_ATTEMPT=3 TRUSTED_CHECKOUT_OUTCOME=failure \
        bash -c "$fallback"
    [ "$status" -eq 1 ]
    grep -q -- '--method PATCH.*check-runs/321' "$log"
    grep -q 'conclusion=failure' "$log"

    : >"$log"
    run env "PATH=$mock_bin:$PATH" TALO_PUBLISH_LOG="$log" \
        TALO_PUBLISH_HEAD="$head" TALO_PUBLISH_NONCE="$nonce" \
        HEAD_SHA="$head" BASE_SHA="$base" CHECK_RUN_ID=322 \
        EXPECTED_EXECUTION_NONCE="$nonce" \
        TRUSTED_RUN_ID=9001 TRUSTED_RUN_ATTEMPT=2 \
        TRUSTED_WORKFLOW_SHA="$controller" SOURCE_RUN_ID=8001 \
        SOURCE_RUN_ATTEMPT=3 TRUSTED_CHECKOUT_OUTCOME=failure \
        bash -c "$fallback"
    [ "$status" -ne 0 ]
    assert_file_lacks --method "$log"
}

@test "stale source base is failed before pending check or replay" {
    local initializer mutant mock_bin log github_output nonce
    local head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    local stale_base=1111111111111111111111111111111111111111
    local current_main=2222222222222222222222222222222222222222
    initializer=$(workflow_step_run "Initialize checkout-independent current-run verdict")
    mock_bin="$BATS_TEST_TMPDIR/stale-base-bin"
    log="$BATS_TEST_TMPDIR/stale-base.log"
    github_output="$BATS_TEST_TMPDIR/stale-base-output"
    mkdir -p "$mock_bin"
    cat >"$mock_bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TALO_PUBLISH_LOG:?}"
if [[ "$*" == "api repos/Arcanada-one/datarim/git/ref/heads/main" ]]; then
    jq -cn --arg sha "${TALO_LIVE_MAIN:?}" \
        '{ref:"refs/heads/main",node_id:"REF_node",url:"https://api.github.com/repos/Arcanada-one/datarim/git/refs/heads/main",object:{sha:$sha,type:"commit",url:("https://api.github.com/repos/Arcanada-one/datarim/git/commits/" + $sha)}}'
else
    jq -cn --argjson id 654 --arg head "${TALO_PUBLISH_HEAD:?}" \
        --arg nonce "${TALO_PUBLISH_NONCE:?}" --arg status "${TALO_PUBLISH_STATUS:?}" \
        '{id:$id,name:"talo-0001-privileged-replay",head_sha:$head,external_id:$nonce,status:$status,conclusion:(if $status == "completed" then "failure" else null end)}'
fi
SH
    chmod +x "$mock_bin/gh"
    nonce=$(printf 'trusted_run_id=%s\ntrusted_run_attempt=%s\nworkflow_sha=%s\nsource_run_id=%s\nsource_run_attempt=%s\nhead_sha=%s\nbase_sha=%s\n' \
        9002 1 "$current_main" 8002 1 "$head" "$stale_base" | sha256sum | cut -d' ' -f1)
    run env "PATH=$mock_bin:$PATH" TALO_PUBLISH_LOG="$log" \
        TALO_PUBLISH_HEAD="$head" TALO_PUBLISH_NONCE="$nonce" \
        TALO_PUBLISH_STATUS=completed GITHUB_OUTPUT="$github_output" \
        HEAD_SHA="$head" BASE_SHA="$stale_base" TRUSTED_RUN_ID=9002 \
        TRUSTED_RUN_ATTEMPT=1 TALO_LIVE_MAIN="$current_main" \
        EVENT_WORKFLOW_SHA="$current_main" \
        SOURCE_RUN_ID=8002 SOURCE_RUN_ATTEMPT=1 bash -c "$initializer"
    [ "$status" -eq 1 ]
    grep -q 'conclusion=failure' "$log"
    assert_file_lacks 'status=in_progress' "$log"
    grep -qx 'check_id=654' "$github_output"
    grep -qx "execution_nonce=$nonce" "$github_output"
    grep -qx 'current_base=false' "$github_output"

    mutant=${initializer/'|| [ "$BASE_SHA" != "$trusted_workflow_sha" ]; then'/'|| false; then'}
    : >"$log"
    : >"$github_output"
    run env "PATH=$mock_bin:$PATH" \
        TALO_PUBLISH_LOG="$log" TALO_PUBLISH_HEAD="$head" \
        TALO_PUBLISH_NONCE="$nonce" TALO_PUBLISH_STATUS=in_progress \
        GITHUB_OUTPUT="$github_output" HEAD_SHA="$head" BASE_SHA="$stale_base" \
        TRUSTED_RUN_ID=9002 TRUSTED_RUN_ATTEMPT=1 \
        TALO_LIVE_MAIN="$current_main" EVENT_WORKFLOW_SHA="$current_main" SOURCE_RUN_ID=8002 \
        SOURCE_RUN_ATTEMPT=1 bash -c "$mutant"
    [ "$status" -eq 0 ]
    grep -q 'status=in_progress' "$log"
    printf '%s\n' 'RED_SENTINEL:stale-base-equality-guard'
}

@test "retired controller is failed against the live main ref before replay" {
    local initializer mock_bin log github_output nonce
    local head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    local retired=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local live_main=2222222222222222222222222222222222222222
    initializer=$(workflow_step_run "Initialize checkout-independent current-run verdict")
    mock_bin="$BATS_TEST_TMPDIR/live-main-race-bin"
    log="$BATS_TEST_TMPDIR/live-main-race.log"
    github_output="$BATS_TEST_TMPDIR/live-main-race-output"
    mkdir -p "$mock_bin"
    cat >"$mock_bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TALO_PUBLISH_LOG:?}"
if [[ "$*" == "api repos/Arcanada-one/datarim/git/ref/heads/main" ]]; then
    jq -cn --arg sha "${TALO_LIVE_MAIN:?}" \
        '{ref:"refs/heads/main",node_id:"REF_node",url:"https://api.github.com/repos/Arcanada-one/datarim/git/refs/heads/main",object:{sha:$sha,type:"commit",url:("https://api.github.com/repos/Arcanada-one/datarim/git/commits/" + $sha)}}'
elif [[ " $* " == *" --method POST "* ]]; then
    jq -cn --argjson id 655 --arg head "${TALO_PUBLISH_HEAD:?}" \
        --arg nonce "${TALO_PUBLISH_NONCE:?}" \
        '{id:$id,name:"talo-0001-privileged-replay",head_sha:$head,external_id:$nonce,status:"completed",conclusion:"failure"}'
fi
SH
    chmod +x "$mock_bin/gh"
    nonce=$(printf 'trusted_run_id=%s\ntrusted_run_attempt=%s\nworkflow_sha=%s\nsource_run_id=%s\nsource_run_attempt=%s\nhead_sha=%s\nbase_sha=%s\n' \
        9003 1 "$live_main" 8003 1 "$head" "$retired" | sha256sum | cut -d' ' -f1)
    run env "PATH=$mock_bin:$PATH" TALO_PUBLISH_LOG="$log" \
        TALO_PUBLISH_HEAD="$head" TALO_PUBLISH_NONCE="$nonce" \
        TALO_LIVE_MAIN="$live_main" GITHUB_OUTPUT="$github_output" \
        HEAD_SHA="$head" BASE_SHA="$retired" TRUSTED_RUN_ID=9003 \
        TRUSTED_RUN_ATTEMPT=1 EVENT_WORKFLOW_SHA="$retired" \
        SOURCE_RUN_ID=8003 SOURCE_RUN_ATTEMPT=1 bash -c "$initializer"
    [ "$status" -eq 1 ] \
        && grep -qx 'api repos/Arcanada-one/datarim/git/ref/heads/main' "$log" \
        && grep -q 'status=completed' "$log" \
        && grep -q 'conclusion=failure' "$log" \
        && assert_file_lacks 'status=in_progress' "$log" \
        && grep -qx 'current_base=false' "$github_output"
}

@test "live main API failure terminalizes before replay allocation" {
    local initializer mock_bin log github_output nonce
    local head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    local controller=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    initializer=$(workflow_step_run "Initialize checkout-independent current-run verdict")
    mock_bin="$BATS_TEST_TMPDIR/live-main-failure-bin"
    log="$BATS_TEST_TMPDIR/live-main-failure.log"
    github_output="$BATS_TEST_TMPDIR/live-main-failure-output"
    mkdir -p "$mock_bin"
    cat >"$mock_bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TALO_PUBLISH_LOG:?}"
if [[ "$*" == "api repos/Arcanada-one/datarim/git/ref/heads/main" ]]; then
    exit 71
elif [[ " $* " == *" --method POST "* ]]; then
    jq -cn --argjson id 656 --arg head "${TALO_PUBLISH_HEAD:?}" \
        --arg nonce "${TALO_PUBLISH_NONCE:?}" \
        '{id:$id,name:"talo-0001-privileged-replay",head_sha:$head,external_id:$nonce,status:"completed",conclusion:"failure"}'
fi
SH
    chmod +x "$mock_bin/gh"
    nonce=$(printf 'trusted_run_id=%s\ntrusted_run_attempt=%s\nworkflow_sha=%s\nsource_run_id=%s\nsource_run_attempt=%s\nhead_sha=%s\nbase_sha=%s\n' \
        9004 1 "$controller" 8004 1 "$head" "$controller" | sha256sum | cut -d' ' -f1)
    run env "PATH=$mock_bin:$PATH" TALO_PUBLISH_LOG="$log" \
        TALO_PUBLISH_HEAD="$head" TALO_PUBLISH_NONCE="$nonce" \
        GITHUB_OUTPUT="$github_output" HEAD_SHA="$head" BASE_SHA="$controller" \
        TRUSTED_RUN_ID=9004 TRUSTED_RUN_ATTEMPT=1 \
        EVENT_WORKFLOW_SHA="$controller" SOURCE_RUN_ID=8004 \
        SOURCE_RUN_ATTEMPT=1 bash -c "$initializer"
    [ "$status" -eq 1 ] \
        && grep -qx 'api repos/Arcanada-one/datarim/git/ref/heads/main' "$log" \
        && grep -q 'status=completed' "$log" \
        && grep -q 'conclusion=failure' "$log" \
        && assert_file_lacks 'status=in_progress' "$log" \
        && grep -qx 'current_base=false' "$github_output"
}

@test "live main response schema and identity guards are load-bearing" {
    local initializer mutant mock_bin log github_output nonce response
    local head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    local live_main=2222222222222222222222222222222222222222
    initializer=$(workflow_step_run "Initialize checkout-independent current-run verdict")
    mock_bin="$BATS_TEST_TMPDIR/live-main-schema-bin"
    log="$BATS_TEST_TMPDIR/live-main-schema.log"
    github_output="$BATS_TEST_TMPDIR/live-main-schema-output"
    mkdir -p "$mock_bin"
    cat >"$mock_bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TALO_PUBLISH_LOG:?}"
if [[ "$*" == "api repos/Arcanada-one/datarim/git/ref/heads/main" ]]; then
    printf '%s\n' "${TALO_REF_RESPONSE:?}"
elif [[ " $* " == *" --method POST "* ]]; then
    jq -cn --argjson id 657 --arg head "${TALO_PUBLISH_HEAD:?}" \
        --arg nonce "${TALO_PUBLISH_NONCE:?}" --arg status "${TALO_PUBLISH_STATUS:?}" \
        '{id:$id,name:"talo-0001-privileged-replay",head_sha:$head,external_id:$nonce,status:$status,conclusion:(if $status == "completed" then "failure" else null end)}'
fi
SH
    chmod +x "$mock_bin/gh"
    nonce=$(printf 'trusted_run_id=%s\ntrusted_run_attempt=%s\nworkflow_sha=%s\nsource_run_id=%s\nsource_run_attempt=%s\nhead_sha=%s\nbase_sha=%s\n' \
        9005 1 "$live_main" 8005 1 "$head" "$live_main" | sha256sum | cut -d' ' -f1)
    while IFS= read -r response; do
        : >"$log"
        : >"$github_output"
        run env "PATH=$mock_bin:$PATH" TALO_PUBLISH_LOG="$log" \
            TALO_PUBLISH_HEAD="$head" TALO_PUBLISH_NONCE="$nonce" \
            TALO_PUBLISH_STATUS=completed TALO_REF_RESPONSE="$response" \
            GITHUB_OUTPUT="$github_output" HEAD_SHA="$head" BASE_SHA="$live_main" \
            TRUSTED_RUN_ID=9005 TRUSTED_RUN_ATTEMPT=1 \
            EVENT_WORKFLOW_SHA="$live_main" SOURCE_RUN_ID=8005 \
            SOURCE_RUN_ATTEMPT=1 bash -c "$initializer"
        [ "$status" -eq 1 ] \
            && grep -q 'status=completed' "$log" \
            && assert_file_lacks 'status=in_progress' "$log" \
            && grep -qx 'current_base=false' "$github_output"
    done <<JSON
{"ref":"refs/heads/main","node_id":"REF_node","url":"https://api.github.com/repos/Arcanada-one/datarim/git/refs/heads/main","extra":true,"object":{"sha":"$live_main","type":"commit","url":"https://api.github.com/repos/Arcanada-one/datarim/git/commits/$live_main"}}
{"ref":"refs/heads/retired","node_id":"REF_node","url":"https://api.github.com/repos/Arcanada-one/datarim/git/refs/heads/main","object":{"sha":"$live_main","type":"commit","url":"https://api.github.com/repos/Arcanada-one/datarim/git/commits/$live_main"}}
{"ref":"refs/heads/main","node_id":"REF_node","url":"https://api.github.com/repos/Arcanada-one/datarim/git/refs/heads/main","object":{"sha":"$live_main","type":"tag","url":"https://api.github.com/repos/Arcanada-one/datarim/git/commits/$live_main"}}
JSON

    response=$(printf '%s' \
        "{\"ref\":\"refs/heads/main\",\"node_id\":\"REF_node\",\"url\":\"https://api.github.com/repos/Arcanada-one/datarim/git/refs/heads/main\",\"extra\":true,\"object\":{\"sha\":\"$live_main\",\"type\":\"commit\",\"url\":\"https://api.github.com/repos/Arcanada-one/datarim/git/commits/$live_main\"}}")
    mutant=${initializer/'select(type == "object" and (keys | sort) == ["node_id","object","ref","url"])'/'select(type == "object")'}
    : >"$log"
    : >"$github_output"
    run env "PATH=$mock_bin:$PATH" TALO_PUBLISH_LOG="$log" \
        TALO_PUBLISH_HEAD="$head" TALO_PUBLISH_NONCE="$nonce" \
        TALO_PUBLISH_STATUS=in_progress TALO_REF_RESPONSE="$response" \
        GITHUB_OUTPUT="$github_output" HEAD_SHA="$head" BASE_SHA="$live_main" \
        TRUSTED_RUN_ID=9005 TRUSTED_RUN_ATTEMPT=1 \
        EVENT_WORKFLOW_SHA="$live_main" SOURCE_RUN_ID=8005 \
        SOURCE_RUN_ATTEMPT=1 bash -c "$mutant"
    [ "$status" -eq 0 ] \
        && grep -q 'status=in_progress' "$log" \
        && printf '%s\n' 'RED_SENTINEL:live-main-closed-schema'
}

@test "event controller freshness guard is independently load-bearing" {
    local initializer mutant mock_bin log github_output nonce
    local head=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    local retired=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local live_main=2222222222222222222222222222222222222222
    initializer=$(workflow_step_run "Initialize checkout-independent current-run verdict")
    mock_bin="$BATS_TEST_TMPDIR/event-controller-bin"
    log="$BATS_TEST_TMPDIR/event-controller.log"
    github_output="$BATS_TEST_TMPDIR/event-controller-output"
    mkdir -p "$mock_bin"
    cat >"$mock_bin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${TALO_PUBLISH_LOG:?}"
if [[ "$*" == "api repos/Arcanada-one/datarim/git/ref/heads/main" ]]; then
    jq -cn --arg sha "${TALO_LIVE_MAIN:?}" \
        '{ref:"refs/heads/main",node_id:"REF_node",url:"https://api.github.com/repos/Arcanada-one/datarim/git/refs/heads/main",object:{sha:$sha,type:"commit",url:("https://api.github.com/repos/Arcanada-one/datarim/git/commits/" + $sha)}}'
elif [[ " $* " == *" --method POST "* ]]; then
    jq -cn --argjson id 658 --arg head "${TALO_PUBLISH_HEAD:?}" \
        --arg nonce "${TALO_PUBLISH_NONCE:?}" --arg status "${TALO_PUBLISH_STATUS:?}" \
        '{id:$id,name:"talo-0001-privileged-replay",head_sha:$head,external_id:$nonce,status:$status,conclusion:(if $status == "completed" then "failure" else null end)}'
fi
SH
    chmod +x "$mock_bin/gh"
    nonce=$(printf 'trusted_run_id=%s\ntrusted_run_attempt=%s\nworkflow_sha=%s\nsource_run_id=%s\nsource_run_attempt=%s\nhead_sha=%s\nbase_sha=%s\n' \
        9006 1 "$live_main" 8006 1 "$head" "$live_main" | sha256sum | cut -d' ' -f1)
    mutant=${initializer/'|| [ "$EVENT_WORKFLOW_SHA" != "$trusted_workflow_sha" ]'/'|| false'}
    run env "PATH=$mock_bin:$PATH" TALO_PUBLISH_LOG="$log" \
        TALO_PUBLISH_HEAD="$head" TALO_PUBLISH_NONCE="$nonce" \
        TALO_PUBLISH_STATUS=in_progress TALO_LIVE_MAIN="$live_main" \
        GITHUB_OUTPUT="$github_output" HEAD_SHA="$head" BASE_SHA="$live_main" \
        TRUSTED_RUN_ID=9006 TRUSTED_RUN_ATTEMPT=1 \
        EVENT_WORKFLOW_SHA="$retired" SOURCE_RUN_ID=8006 \
        SOURCE_RUN_ATTEMPT=1 bash -c "$mutant"
    [ "$status" -eq 0 ] \
        && grep -q 'status=in_progress' "$log" \
        && printf '%s\n' 'RED_SENTINEL:event-controller-freshness'
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
systemctl stop "$UNIT_NAME"|true|missing:runner-runtime-contract
id=$(ensure_group)|id=1|mismatch:registration-safety-order
runner=$(wait_for_exact_runner "$id" registered)|runner=true|mismatch:registration-safety-order
stop_and_disable_runner_service|true|mismatch:group-reconciliation-safety-order
bind_pre_reconcile_roster "$id"|true|mismatch:group-reconciliation-safety-order
ACTIONS_RUNNER_INPUT_TOKEN="$token"|ACTIONS_RUNNER_INPUT_TOKEN=|missing:runner-runtime-contract
MUTANTS
}

@test "stale-run and executable-race semantic guards are load-bearing" {
    local controller="$FIXTURE/dev-tools/trusted-talo-0001-replay.sh"
    local publisher="$FIXTURE/dev-tools/publish-talo-0001-check.sh"
    local provisioner="$FIXTURE/dev-tools/provision-talo-0001-trusted-runner.sh"
    sed -i '/: >"$OUTPUT"/d' "$controller"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *'missing:candidate-object-contract:: >"$OUTPUT"'* ]]

    cp "$ROOT/dev-tools/trusted-talo-0001-replay.sh" "$controller"
    sed -i 's/trusted_run_id == \$trusted_run_id/true/' "$publisher"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *'missing:candidate-object-contract:trusted_run_id'* ]]

    cp "$ROOT/dev-tools/publish-talo-0001-check.sh" "$publisher"
    python3 - "$provisioner" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
needle = "verify_runner_payload_ownership"
head, tail = source.rsplit(needle, 1)
path.write_text(head + "true # removed-preexec-owner-check" + tail, encoding="utf-8")
PY
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *'mismatch:runner-preexec-revalidation-cardinality'* ]]

    cp "$ROOT/dev-tools/provision-talo-0001-trusted-runner.sh" "$provisioner"
    sed -i '/chown root:root "$RUNNER_DIR"/a\    chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"' \
        "$provisioner"
    run_check
    [ "$status" -eq 1 ]
    [[ "$output" == *'forbidden:runner-owned-executable-payload'* ]]
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
settings["AgentId"] == runner_id|True
RUNNER_ARCHIVE_SHA256=04cf0be1aff4c3ec3554466c39124ca250e3effd8873bb7e8d68535aa9505d5d|RUNNER_ARCHIVE_SHA256=0000000000000000000000000000000000000000000000000000000000000000
RUNNER_PAYLOAD_TREE_SHA256=802a94df6d2aee3e458620b5a1175f8646f195092081d3285b8b0dd33c8cc8f6|RUNNER_PAYLOAD_TREE_SHA256=0000000000000000000000000000000000000000000000000000000000000000
--disableupdate|--replace
install -d -o root -g root -m 0755 "$RUNNER_DIR"|install -d -o "$RUNNER_USER" -g "$RUNNER_USER" -m 0755 "$RUNNER_DIR"
systemctl disable --now "$UNIT_NAME"|systemctl stop "$UNIT_NAME"
if api --method DELETE|if true
fresh_registration=true|fresh_registration=false
MUTANTS

    sed -i \
        's#ExecStart=/srv/talo-0001-trusted/runner/bin/Runner.Listener run#ExecStart=/srv/talo-0001-trusted/runner/run.sh#' \
        "$unit"
    run_check
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'missing:runner-unit:ExecStart='* ]]
}

@test "every bootstrap path has an exact Git-object mode in one main commit" {
    setup_provision_runtime
    chmod -x "$PROVISIONER"
    git -C "$FIXTURE" add dev-tools/provision-talo-0001-trusted-runner.sh
    git -C "$FIXTURE" commit -qm non-executable-provisioner
    MOCK_MAIN_COMMIT=$(git -C "$FIXTURE" rev-parse HEAD)
    chmod +x "$PROVISIONER"
    TALO_MOCK_PRESERVE_MAIN_COMMIT=1 run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'trusted bootstrap Git object rejected: dev-tools/provision-talo-0001-trusted-runner.sh'* ]]
    assert_file_lacks '^systemctl ' "$MOCK_LOG"

    setup_provision_runtime
    git -C "$FIXTURE" rm -q dev-tools/systemd/talo-0001-trusted-runner.service
    git -C "$FIXTURE" commit -qm missing-unit
    MOCK_MAIN_COMMIT=$(git -C "$FIXTURE" rev-parse HEAD)
    TALO_MOCK_PRESERVE_MAIN_COMMIT=1 run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'trusted bootstrap Git object rejected: dev-tools/systemd/talo-0001-trusted-runner.service'* ]]
    assert_file_lacks '^systemctl ' "$MOCK_LOG"
}

@test "one live main commit supplies immutable root-staged bootstrap blobs" {
    setup_provision_runtime
    run_provision_runtime
    [ "$status" -eq 0 ] \
        && [ "$(grep -c 'git/ref/heads/main' "$MOCK_LOG")" -eq 2 ] \
        && assert_file_lacks 'contents/.github/workflows/talo-0001-trusted-replay.yml?ref=main' "$MOCK_LOG" \
        && assert_file_lacks 'contents/dev-tools/provision-talo-0001-trusted-runner.sh?ref=main' "$MOCK_LOG" \
        && assert_file_lacks 'contents/dev-tools/systemd/talo-0001-trusted-runner.service?ref=main' "$MOCK_LOG" \
        && grep -Eq '^install .* /tmp/talo-trusted-bootstrap\.[^/]+/dev-tools/systemd/talo-0001-trusted-runner.service /etc/systemd/system/talo-0001-trusted-runner.service$' \
            "$MOCK_LOG"
}

@test "main advance between loader and sealed worker performs no mutation" {
    local initial_commit advanced_commit
    setup_provision_runtime
    initial_commit=$MOCK_MAIN_COMMIT
    printf '%s\n' '# main advanced' >>"$FIXTURE/.github/workflows/talo-0001-trusted-replay.yml"
    git -C "$FIXTURE" add .github/workflows/talo-0001-trusted-replay.yml
    git -C "$FIXTURE" commit -qm advanced-main
    advanced_commit=$(git -C "$FIXTURE" rev-parse HEAD)
    MOCK_MAIN_COMMIT=$initial_commit
    TALO_MOCK_MAIN_SEQUENCE=advance \
        TALO_MOCK_ADVANCED_MAIN_COMMIT=$advanced_commit \
        TALO_MOCK_PRESERVE_MAIN_COMMIT=1 run_provision_runtime
    [ "$status" -eq 1 ] \
        && [[ "$output" == *'trusted main advanced before provisioning'* ]] \
        && [ "$(grep -c 'git/ref/heads/main' "$MOCK_LOG")" -eq 2 ]
    assert_file_lacks '^systemctl ' "$MOCK_LOG"
    assert_file_lacks '--method PATCH' "$MOCK_LOG"
    assert_file_lacks '--method PUT' "$MOCK_LOG"
}

@test "sealed provisioner exec transition is behaviorally load-bearing" {
    setup_provision_runtime
    sed -i 's#^        exec /usr/bin/env \\#        /usr/bin/env \\#' "$PROVISIONER"
    run_provision_runtime
    [ "$status" -ne 0 ]
    [ "$(grep -c '^systemctl stop' "$MOCK_LOG")" -ge 2 ]
    printf '%s\n' 'RED_SENTINEL:sealed-provisioner-exec-transition'
}

@test "post-verification mutable unit swap cannot change installed bytes" {
    local trusted_unit hostile_unit
    setup_provision_runtime
    trusted_unit="$BATS_TEST_TMPDIR/trusted-unit"
    hostile_unit="$BATS_TEST_TMPDIR/hostile-unit"
    cp "$FIXTURE/dev-tools/systemd/talo-0001-trusted-runner.service" "$trusted_unit"
    printf '%s\n' '[Service]' 'ExecStart=/bin/false' >"$hostile_unit"
    TALO_MOCK_SWAP_UNIT_SOURCE="$hostile_unit" run_provision_runtime
    [ "$status" -eq 0 ] \
        && [ -L "$FIXTURE/dev-tools/systemd/talo-0001-trusted-runner.service" ] \
        && cmp -s "$trusted_unit" "$MOCK_INSTALLED_UNIT" \
        && ! cmp -s "$hostile_unit" "$MOCK_INSTALLED_UNIT"
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
        [[ "$output" == *'ERROR: trusted main ref could not be resolved'* ]]
        assert_file_lacks '^systemctl ' "$log"
    done
}

@test "exact registered runner reaches online idle service success" {
    setup_provision_runtime
    run_provision_runtime
    [ "$status" -eq 0 ]
    grep -q '^systemctl stop' "$MOCK_LOG"
    grep -q '^systemctl enable --now' "$MOCK_LOG"
    [ "$(grep -c 'runner-groups/42/runners' "$MOCK_LOG")" -eq 3 ]
}

@test "trusted group rejects every extra member even when its labels match" {
    setup_provision_runtime
    TALO_MOCK_RUNNERS_MODE=extra run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'runner is not the exact trusted group member'* ]]
    grep -q '^systemctl disable --now' "$MOCK_LOG"
    assert_file_lacks '--method PATCH' "$MOCK_LOG"
    assert_file_lacks '--method PUT' "$MOCK_LOG"
    assert_file_lacks '^systemctl enable' "$MOCK_LOG"
}

@test "unconfigured host rejects a pre-existing remote runner before reconciliation" {
    setup_provision_runtime
    prepare_fresh_runner_payload
    TALO_MOCK_RUNNERS_MODE=unbound-pre run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'pre-reconciliation roster is not empty'* ]]
    grep -q '^systemctl disable --now' "$MOCK_LOG"
    assert_file_lacks '--method PATCH' "$MOCK_LOG"
    assert_file_lacks '--method PUT' "$MOCK_LOG"
    roster_line=$(grep -n 'runner-groups/42/runners' "$MOCK_LOG" | head -1 | cut -d: -f1)
    disable_line=$(grep -n '^systemctl disable --now' "$MOCK_LOG" | head -1 | cut -d: -f1)
    [ "$disable_line" -lt "$roster_line" ]
}

@test "local runner identity and payload failure leave service disabled before re-enable" {
    setup_provision_runtime
    sed -i 's/"AgentId":7001/"AgentId":9999/' "$RUNNER_FIXTURE/.runner"
    run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'local runner registration mismatch'* ]]
    grep -q '^systemctl disable --now' "$MOCK_LOG"
    assert_file_lacks '--method PATCH' "$MOCK_LOG"
    assert_file_lacks '--method PUT' "$MOCK_LOG"
    assert_file_lacks '^systemctl enable' "$MOCK_LOG"

    setup_provision_runtime
    printf '%s\n' tampered-support >"$RUNNER_FIXTURE/externals/support.bin"
    run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'runner payload tree mismatch'* ]]
    grep -q '^systemctl disable --now' "$MOCK_LOG"
    assert_file_lacks '--method PATCH' "$MOCK_LOG"
    assert_file_lacks '--method PUT' "$MOCK_LOG"
    assert_file_lacks '^systemctl enable' "$MOCK_LOG"
}

@test "incomplete local state rejects an empty remote roster before reconciliation" {
    setup_provision_runtime
    prepare_fresh_runner_payload
    mkdir -p "$RUNNER_FIXTURE"
    : >"$RUNNER_FIXTURE/.credentials"
    TALO_MOCK_RUNNERS_MODE=fresh run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'interrupted runner registration could not be resealed'* ]]
    grep -q '^systemctl disable --now' "$MOCK_LOG"
    assert_file_lacks '--method PATCH' "$MOCK_LOG"
    assert_file_lacks '--method PUT' "$MOCK_LOG"
}

@test "hostile runner service endpoint is rejected before group authorization" {
    setup_provision_runtime
    sed -i 's#https://pipelinesghubeus26.actions.githubusercontent.com/AbCdEfGhIjKlMnOpQrStUvWxYz012345/#https://attacker.example/collect/#' \
        "$RUNNER_FIXTURE/.runner"
    run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'local runner registration mismatch'* ]]
    assert_file_lacks '--method PATCH' "$MOCK_LOG"
    assert_file_lacks '--method PUT' "$MOCK_LOG"
}

@test "every resealed hostile runner identity field is rejected before authorization" {
    local original_runner original_credentials original_rsa
    setup_provision_runtime
    original_runner="$BATS_TEST_TMPDIR/identity-runner.original"
    original_credentials="$BATS_TEST_TMPDIR/identity-credentials.original"
    original_rsa="$BATS_TEST_TMPDIR/identity-rsa.original"
    cp "$RUNNER_FIXTURE/.runner" "$original_runner"
    cp "$RUNNER_FIXTURE/.credentials" "$original_credentials"
    cp "$RUNNER_FIXTURE/.credentials_rsaparams" "$original_rsa"
    while IFS='|' read -r target expression value; do
        make_runner_fixture_editable
        cp "$original_runner" "$RUNNER_FIXTURE/.runner"
        cp "$original_credentials" "$RUNNER_FIXTURE/.credentials"
        cp "$original_rsa" "$RUNNER_FIXTURE/.credentials_rsaparams"
        jq "$expression = $value" "$RUNNER_FIXTURE/$target" \
            >"$RUNNER_FIXTURE/$target.next"
        mv "$RUNNER_FIXTURE/$target.next" "$RUNNER_FIXTURE/$target"
        reseal_registration_identity
        : >"$MOCK_LOG"
        run_provision_runtime
        [ "$status" -eq 1 ]
        [[ "$output" == *'local runner registration mismatch'* ]]
        assert_file_lacks '--method PATCH' "$MOCK_LOG"
        assert_file_lacks '--method PUT' "$MOCK_LOG"
    done <<'MUTANTS'
.runner|.ServerUrl|"https://attacker.example/collect/"
.runner|.ServerUrlV2|"https://attacker.example/broker/"
.runner|.UseV2Flow|false
.runner|.UseRunnerAdminFlow|false
.credentials|.Data.authorizationUrl|"https://attacker.example/oauth/"
.credentials|.Data.authorizationUrlV2|"https://attacker.example/broker/"
.credentials|.Data.clientId|"00000000-0000-0000-0000-000000000000"
.credentials_rsaparams|.exponent|"AAE="
MUTANTS
}

@test "registration identity seal is load-bearing after semantic validation" {
    setup_provision_runtime
    jq '.runner_id = 7002' "$RUNNER_FIXTURE/.talo-registration-seal" \
        >"$RUNNER_FIXTURE/.talo-registration-seal.next"
    mv "$RUNNER_FIXTURE/.talo-registration-seal.next" \
        "$RUNNER_FIXTURE/.talo-registration-seal"
    run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'local runner registration mismatch'* ]]
    assert_file_lacks '--method PATCH' "$MOCK_LOG"
    assert_file_lacks '--method PUT' "$MOCK_LOG"
}

@test "registration stop failure is fatal before runner configuration" {
    setup_provision_runtime
    TALO_MOCK_STOP_FAILURE=1 run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'unable to stop trusted runner service'* ]]
    grep -q '^systemctl disable --now' "$MOCK_LOG"
    [ "$(cat "$MOCK_SERVICE_STATE")" = disabled ]
    assert_file_lacks '^config.sh ' "$MOCK_LOG"
}

@test "active runner is disabled before any group policy mutation" {
    setup_provision_runtime
    TALO_MOCK_GROUP_MUTATION_FAILURE=1 run_provision_runtime
    [ "$status" -eq 1 ]
    [ "$(cat "$MOCK_SERVICE_STATE")" = disabled ]
    disable_line=$(grep -n '^systemctl disable --now' "$MOCK_LOG" | head -1 | cut -d: -f1)
    patch_line=$(grep -n -- '--method PATCH' "$MOCK_LOG" | head -1 | cut -d: -f1)
    [ "$disable_line" -lt "$patch_line" ]
    assert_file_lacks '^config.sh ' "$MOCK_LOG"
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
    assert_file_lacks '^sudo .*talo-runner-payload' "$MOCK_LOG"
}

@test "registration token uses pinned non-argv runner input transport" {
    setup_provision_runtime
    prepare_fresh_runner_payload
    TALO_MOCK_RUNNERS_MODE=fresh run_provision_runtime
    [ "$status" -eq 0 ]
    grep -q '^config.sh --unattended' "$MOCK_LOG"
    assert_file_lacks 'fixture-token' "$MOCK_LOG"
    assert_file_lacks 'fixture-token' "$MOCK_CONFIG_CMDLINE"
    [ -f "$MOCK_CONFIG_ENV_REMOVED" ]
}

@test "same-UID replacement race is rejected before token materialization" {
    setup_provision_runtime
    prepare_fresh_runner_payload
    TALO_MOCK_RUNNERS_MODE=fresh TALO_MOCK_RUNNER_PROCESS=1 \
        run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'runner identity is not quiescent before reconciliation'* ]]
    assert_file_lacks 'registration-token' "$MOCK_LOG"
    assert_file_lacks '^config.sh ' "$MOCK_LOG"
    [ "$(cat "$MOCK_SERVICE_STATE")" = disabled ]
}

@test "existing registration rejects a detached runner identity before policy mutation" {
    setup_provision_runtime
    TALO_MOCK_RUNNERS_MODE=one TALO_MOCK_RUNNER_PROCESS=1 \
        run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'runner identity is not quiescent before reconciliation'* ]]
    assert_file_lacks '--method PATCH' "$MOCK_LOG"
    assert_file_lacks '--method PUT' "$MOCK_LOG"
    assert_file_lacks '^systemctl enable' "$MOCK_LOG"
}

@test "existing registration rechecks quiescence immediately before service start" {
    setup_provision_runtime
    TALO_MOCK_RUNNERS_MODE=one TALO_MOCK_RUNNER_PROCESS=late \
        run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'runner identity is not quiescent before service start'* ]]
    grep -q -- '--method PATCH' "$MOCK_LOG"
    grep -q -- '--method PUT' "$MOCK_LOG"
    assert_file_lacks '^systemctl enable' "$MOCK_LOG"

    python3 - "$PROVISIONER" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
old = '''    assert_runner_user_quiescent || {
        abort_runner_transaction "$id" "$fresh_registration" \\
            "$pre_registration_empty" "$runner_id" \\
            "runner identity is not quiescent before service start"
    }
'''
assert source.count(old) == 1
path.write_text(source.replace(old, ""), encoding="utf-8")
PY
    : >"$MOCK_LOG"
    printf '%s\n' 0 >"$MOCK_PGREP_COUNTER"
    TALO_MOCK_RUNNERS_MODE=one TALO_MOCK_RUNNER_PROCESS=late \
        run_provision_runtime
    [ "$status" -eq 0 ]
    grep -q '^systemctl enable --now' "$MOCK_LOG"
    printf '%s\n' 'RED_SENTINEL:prestart-quiescence-call'
}

@test "post-start process must be the exact listener identity in the service cgroup" {
    setup_provision_runtime
    printf '0::/system.slice/hostile.service\n' >"$PROC_FIXTURE/4242/cgroup"
    TALO_MOCK_RUNNERS_MODE=one run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'started runner process/cgroup identity mismatch'* ]]
    [ "$(cat "$MOCK_SERVICE_STATE")" = disabled ]

    sed -i 's/    verify_started_runner_process || {/    true || {/' \
        "$PROVISIONER"
    : >"$MOCK_LOG"
    TALO_MOCK_RUNNERS_MODE=one run_provision_runtime
    [ "$status" -eq 0 ]
    grep -q '^systemctl enable --now' "$MOCK_LOG"
    printf '%s\n' 'RED_SENTINEL:post-start-process-cgroup-boundary'
}

@test "runner UID cannot replace the exact executable payload after hardening" {
    setup_provision_runtime
    prepare_fresh_runner_payload
    TALO_MOCK_RUNNERS_MODE=fresh run_provision_runtime
    [ "$status" -eq 0 ]
    local expected hostile
    expected=$(sha256sum "$RUNNER_FIXTURE/config.sh" | cut -d' ' -f1)
    chmod 0755 "$BATS_TEST_TMPDIR"
    hostile="$BATS_TEST_TMPDIR/hostile-config.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'printf stolen-token' >"$hostile"
    chmod 0644 "$hostile"
    run sudo -u "$TEST_RUNNER_USER" mv "$hostile" "$RUNNER_FIXTURE/config.sh"
    [ "$status" -ne 0 ]
    [ "$(sha256sum "$RUNNER_FIXTURE/config.sh" | cut -d' ' -f1)" = "$expected" ]
    [ "$(stat -c '%u:%g:%a' "$RUNNER_FIXTURE")" = 0:0:755 ]
    [ "$(stat -c '%u:%g' "$RUNNER_FIXTURE/config.sh")" = 0:0 ]
}

@test "config-time runner UID cannot unlink root payload while token is live" {
    local path
    setup_provision_runtime
    prepare_fresh_runner_payload
    path=$BATS_TEST_TMPDIR
    while [ "$path" != /tmp ]; do
        chmod o+x "$path"
        path=$(dirname "$path")
    done
    chmod 0666 "$MOCK_LOG"
    MOCK_CONFIG_STARTED="$RUNNER_FIXTURE/_diag/config-started"
    MOCK_CONFIG_CMDLINE="$RUNNER_FIXTURE/_diag/config-cmdline"
    MOCK_CONFIG_ENV_REMOVED="$RUNNER_FIXTURE/_diag/config-env-removed"
    TALO_MOCK_RUNNERS_MODE=fresh TALO_MOCK_REPLACE_EXEC=1 \
        TALO_MOCK_REAL_UID=1 \
        run_provision_runtime
    [ "$status" -eq 0 ]
    grep -q '^config-replace-attempt$' "$MOCK_LOG"
    grep -q '^#!/usr/bin/env bash$' "$RUNNER_FIXTURE/config.sh"
    [ "$(stat -c '%u:%g' "$RUNNER_FIXTURE/config.sh")" = 0:0 ]
}

@test "next transaction reseals an interrupted registration directory before policy I/O" {
    setup_provision_runtime
    prepare_fresh_runner_payload
    local original="$BATS_TEST_TMPDIR/interrupted-registration.original"
    cp "$PROVISIONER" "$original"
    sed -i '0,/        set +e/{s/        set +e/        exit 88\n        set +e/}' \
        "$PROVISIONER"
    TALO_MOCK_RUNNERS_MODE=fresh run_provision_runtime
    [ "$status" -eq 88 ]
    runner_gid=$TEST_RUNNER_GID
    [ "$(stat -c '%u:%g:%a' "$RUNNER_FIXTURE")" = "0:$runner_gid:3775" ]

    cp "$original" "$PROVISIONER"
    : >"$MOCK_LOG"
    TALO_MOCK_RUNNERS_MODE=fresh run_provision_runtime
    [ "$status" -eq 0 ]
    [ "$(stat -c '%u:%g:%a' "$RUNNER_FIXTURE")" = 0:0:755 ]
    seal_line=$(grep -n '^chmod 0755 .*runner$' "$MOCK_LOG" | head -1 | cut -d: -f1)
    patch_line=$(grep -n -- '--method PATCH' "$MOCK_LOG" | head -1 | cut -d: -f1)
    [ "$seal_line" -lt "$patch_line" ]
}

@test "negative file assertion fails on a present forbidden command" {
    local log="$BATS_TEST_TMPDIR/forbidden-command.log"
    printf '%s\n' 'systemctl enable --now forbidden.service' >"$log"
    run assert_file_lacks '^systemctl enable' "$log"
    [ "$status" -ne 0 ]
    [[ "$output" == *'unexpected pattern'* ]]
}

@test "pre-reconciliation roster order mutant authorizes the hostile member" {
    setup_provision_runtime
    python3 - "$PROVISIONER" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
old = '''    stop_and_disable_runner_service || return 1
    seal_interrupted_registration_directory || {
        echo "ERROR: interrupted runner registration could not be resealed" >&2
        return 1
    }
    verify_runner_account || {
        echo "ERROR: runner account boundary mismatch before reconciliation" >&2
        return 1
    }
    assert_runner_user_quiescent || {
        echo "ERROR: runner identity is not quiescent before reconciliation" >&2
        return 1
    }
    bind_pre_reconcile_roster "$id" || return 1
    reconcile_group "$id"
'''
new = '''    stop_and_disable_runner_service || return 1
    seal_interrupted_registration_directory || {
        echo "ERROR: interrupted runner registration could not be resealed" >&2
        return 1
    }
    verify_runner_account || {
        echo "ERROR: runner account boundary mismatch before reconciliation" >&2
        return 1
    }
    assert_runner_user_quiescent || {
        echo "ERROR: runner identity is not quiescent before reconciliation" >&2
        return 1
    }
    reconcile_group "$id" || return 1
    bind_pre_reconcile_roster "$id"
'''
assert source.count(old) == 1
path.write_text(source.replace(old, new), encoding="utf-8")
PY
    TALO_MOCK_RUNNERS_MODE=extra run_provision_runtime
    [ "$status" -eq 1 ]
    grep -q -- '--method PATCH' "$MOCK_LOG"
    grep -q -- '--method PUT' "$MOCK_LOG"
    printf '%s\n' 'RED_SENTINEL:pre-reconciliation-roster-order'
}

@test "registration argv mutant exposes the token and is rejected" {
    setup_provision_runtime
    prepare_fresh_runner_payload
    python3 - "$PROVISIONER" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
old = '''        ACTIONS_RUNNER_INPUT_TOKEN="$token" \\
            sudo --preserve-env=ACTIONS_RUNNER_INPUT_TOKEN -u "$RUNNER_USER" \\
            "$RUNNER_DIR/config.sh" --unattended \\
            --url "https://github.com/$ORG" \\
'''
new = '''        sudo -u "$RUNNER_USER" \\
            "$RUNNER_DIR/config.sh" --unattended \\
            --url "https://github.com/$ORG" --token "$token" \\
'''
assert source.count(old) == 1
path.write_text(source.replace(old, new), encoding="utf-8")
PY
    TALO_MOCK_RUNNERS_MODE=fresh run_provision_runtime
    [ "$status" -eq 1 ]
    grep -q -- 'fixture-token' "$MOCK_LOG"
    printf '%s\n' 'RED_SENTINEL:runner-token-in-argv'
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

@test "remote registration without local config is discovered deleted and retried" {
    setup_provision_runtime
    prepare_fresh_runner_payload
    TALO_MOCK_RUNNERS_MODE=remote-before-local \
        TALO_MOCK_CONFIG_REMOTE_ONLY=1 TALO_MOCK_DELETE_FAILURES=1 \
        run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'runner configuration failed'* ]]
    [ "$(grep -c -- '--method DELETE orgs/Arcanada-one/actions/runners/7001' "$MOCK_LOG")" -eq 2 ]
    [ -f "$MOCK_REGISTRATION_REMOVED" ]
    [ "$(cat "$MOCK_SERVICE_STATE")" = disabled ]
    [ ! -e "$RUNNER_FIXTURE/.runner" ]
}

@test "hostile post-registration roster preserves local evidence while disabled" {
    setup_provision_runtime
    prepare_fresh_runner_payload
    TALO_MOCK_RUNNERS_MODE=fresh-hostile TALO_MOCK_CONFIG_FAILURE=1 \
        run_provision_runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *'rollback could not prove fail-closed state'* ]]
    [ "$(cat "$MOCK_SERVICE_STATE")" = disabled ]
    [ -e "$RUNNER_FIXTURE/.runner" ]
    [ ! -e "$MOCK_REGISTRATION_REMOVED" ]
}

@test "errexit prevents hostile loop restoration from masking a known survivor" {
    local vulnerable="$BATS_TEST_TMPDIR/vulnerable.sh"
    local guarded="$BATS_TEST_TMPDIR/guarded.sh"
    cat >"$vulnerable" <<'BATS'
#!/usr/bin/env bash
for mutant in known-survivor; do
    false
    true # hostile restoration used to mask the failed assertion
done
BATS
    cat >"$guarded" <<'BATS'
#!/usr/bin/env bash
set -euo pipefail
for mutant in known-survivor; do
    false
    true # must never execute after the failed assertion
done
BATS
    run bash "$vulnerable"
    [ "$status" -eq 0 ]
    run bash "$guarded"
    [ "$status" -ne 0 ]
}

@test "global assertion errexit is itself load-bearing" {
    grep -q '^set -euo pipefail$' "$BATS_TEST_FILENAME"
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

    make_runner_fixture_editable
    setup_provision_runtime
    cp "$original" "$PROVISIONER"
    sed -i \
        's/    disable_runner_service || rollback_failed=true/    true/' \
        "$PROVISIONER"
    TALO_MOCK_RUNNERS_MODE=busy run_provision_runtime
    [ "$status" -eq 1 ]
    [ "$(cat "$MOCK_SERVICE_STATE")" = enabled ]

    make_runner_fixture_editable
    setup_provision_runtime
    cp "$original" "$PROVISIONER"
    prepare_fresh_runner_payload
    python3 - "$PROVISIONER" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
old = '''    if [ "$fresh_registration" = true ]; then
        rollback_new_registration "$id" "$pre_registration_empty" \\
            "$known_runner_id" \\
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
    sed -i 's/settings\["AgentId"\] == runner_id/True/' "$PROVISIONER"
    sed -i 's/"AgentId":7001/"AgentId":9999/' "$RUNNER_FIXTURE/.runner"
    reseal_registration_identity
    run_provision_runtime
    [ "$status" -eq 0 ]

    make_runner_fixture_editable
    cp "$original" "$PROVISIONER"
    sed -i 's/\[ "$actual" = "$RUNNER_PAYLOAD_TREE_SHA256" \]/true/' "$PROVISIONER"
    sed -i 's/"AgentId":9999/"AgentId":7001/' "$RUNNER_FIXTURE/.runner"
    reseal_registration_identity
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
old = '''    systemctl stop "$UNIT_NAME" 2>/dev/null || {
        disable_runner_service || \\
            echo "ERROR: trusted runner rollback could not prove fail-closed state" >&2
        echo "ERROR: unable to stop trusted runner service" >&2
        return 1
    }
'''
new = '''    true
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
    "id": 8001,
    "run_attempt": 1,
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
        "base": {"ref": "main", "sha": "cccccccccccccccccccccccccccccccccccccccc", "repo": {"url": "https://api.github.com/repos/Arcanada-one/datarim"}},
    }],
}}
Path(sys.argv[1]).write_text(json.dumps(payload), encoding="utf-8")
PY
    run env TALO_TRUSTED_WORKFLOW_SHA=cccccccccccccccccccccccccccccccccccccccc \
        "$preflight" "$event"
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
        run env TALO_TRUSTED_WORKFLOW_SHA=cccccccccccccccccccccccccccccccccccccccc \
            "$preflight" "$event"
        [ "$status" -ne 0 ]
        python3 - "$event" "$expression" <<'PY'
import json
from pathlib import Path
import sys

# Restore from the code-owned baseline by reversing the single hostile value.
defaults = {
    "workflow_run.id": 8001,
    "workflow_run.run_attempt": 1,
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
    "workflow_run.pull_requests.0.base.sha": "cccccccccccccccccccccccccccccccccccccccc",
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
workflow_run.id|0
workflow_run.run_attempt|0
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
workflow_run.pull_requests.0.base.sha|"not-a-sha"
workflow_run.pull_requests.0.base.repo.url|"https://api.github.com/repos/attacker/fork"
MUTANTS
}
