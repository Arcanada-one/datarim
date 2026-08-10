#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/dev-tools/preflight-caller-contract.sh"
    ACTION="$REPO_ROOT/.github/actions/preflight-caller-contract/action.yml"
    REGISTRY="$REPO_ROOT/.github/actions/preflight-caller-contract/consumers.yml"
    FIXTURES="$REPO_ROOT/tests/fixtures/preflight-caller-contract"
    TEST_ROOT="$BATS_TEST_TMPDIR/repository"
    WORKFLOW_REL=".github/workflows/deploy.yml"
    WORKFLOW="$TEST_ROOT/$WORKFLOW_REL"
    ACTION_REF="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    mkdir -p "$(dirname "$WORKFLOW")"
    cp "$FIXTURES/valid.yml" "$WORKFLOW"
    git -C "$TEST_ROOT" init -q
    git -C "$TEST_ROOT" config user.name "Datarim Tests"
    git -C "$TEST_ROOT" config user.email "tests@invalid.example"
    git -C "$TEST_ROOT" add "$WORKFLOW_REL"
    git -C "$TEST_ROOT" commit -qm fixture
}

run_contract() {
    local action_repository="${CALLER_ACTION_REPOSITORY_OVERRIDE:-Arcanada-one/datarim}"
    local action_ref="${CALLER_ACTION_REF_OVERRIDE:-$ACTION_REF}"
    local caller_repository="${CALLER_REPOSITORY_OVERRIDE:-Arcanada-one/muneral}"
    local vault_addr="${CALLER_VAULT_ADDR_OVERRIDE-https://vault.internal:8200}"
    local yq_bin="${CALLER_YQ_BIN_OVERRIDE:-$(command -v yq)}"
    local workflow_ref="${CALLER_WORKFLOW_REF_OVERRIDE:-$caller_repository/$WORKFLOW_REL@refs/pull/42/merge}"
    if [ "${CALLER_SKIP_SYNC:-false}" != true ]; then
        git -C "$TEST_ROOT" add "$WORKFLOW_REL"
        git -C "$TEST_ROOT" commit --amend --no-edit -q
    fi
    local workflow_sha
    workflow_sha="$(git -C "$TEST_ROOT" rev-parse HEAD)"
    run env \
        GITHUB_WORKSPACE="$TEST_ROOT" \
        PREFLIGHT_CALLER_ACTION_REPOSITORY="$action_repository" \
        PREFLIGHT_CALLER_ACTION_REF="$action_ref" \
        PREFLIGHT_CALLER_GITHUB_REPOSITORY="$caller_repository" \
        PREFLIGHT_CALLER_WORKFLOW_REF="$workflow_ref" \
        PREFLIGHT_CALLER_WORKFLOW_SHA="$workflow_sha" \
        PREFLIGHT_CALLER_VAULT_ADDR="$vault_addr" \
        PREFLIGHT_CALLER_YQ_BIN="$yq_bin" \
        "$SCRIPT"
}

mutate() {
    yq -i "$1" "$WORKFLOW"
}

restore_fixture() {
    cp "$FIXTURES/valid.yml" "$WORKFLOW"
}

assert_status_is() {
    local expected="$1"
    if [ "$status" -ne "$expected" ]; then
        echo "expected status $expected, got $status; output: $output" >&2
        return 1
    fi
}

assert_output_has() {
    local expected="$1"
    if [[ "$output" != *"$expected"* ]]; then
        echo "expected output to contain '$expected'; output: $output" >&2
        return 1
    fi
}

assert_rejected() {
    local field="$1"
    run_contract
    assert_status_is 1 || return 1
    assert_output_has "$field" || return 1
}

@test "composite action pins yq, exposes only vault-addr, and wires immutable contexts" {
    run yq -er '
      .runs.using == "composite" and
      (.inputs | keys | join(",")) == "vault-addr" and
      .inputs."vault-addr".required == true and
      (.runs.steps | length) == 2 and
      .runs.steps[0].env.YQ_VERSION == "v4.44.3" and
      .runs.steps[0].env.YQ_SHA256 == "a2c097180dd884a8d50c956ee16a9cec070f30a7947cf4ebf87d5f36213e9ed7" and
      ([.runs.steps[] | select(.run == "\"${{ github.action_path }}/../../../dev-tools/preflight-caller-contract.sh\"")] | length == 1)
    ' "$ACTION"
    assert_status_is 0 || return 1

    for binding in \
        'PREFLIGHT_CALLER_ACTION_REF: ${{ github.action_ref }}' \
        'PREFLIGHT_CALLER_ACTION_REPOSITORY: ${{ github.action_repository }}' \
        'PREFLIGHT_CALLER_WORKFLOW_REF: ${{ github.workflow_ref }}' \
        'PREFLIGHT_CALLER_WORKFLOW_SHA: ${{ github.workflow_sha }}' \
        'PREFLIGHT_CALLER_VAULT_ADDR: ${{ inputs.vault-addr }}' \
        'PREFLIGHT_CALLER_YQ_BIN: ${{ runner.temp }}/datarim-preflight-caller-contract/yq'; do
        run grep -F "$binding" "$ACTION"
        assert_status_is 0 || return 1
    done

    run yq -er '."schema-version" == 1 and .consumers."Arcanada-one/muneral"."service-name" == "muneral"' "$REGISTRY"
    assert_status_is 0
}

@test "valid registered Muneral workflow passes with list needs and multiline checks" {
    run_contract
    assert_status_is 0 || return 1
    [ "$output" = "preflight caller contract: PASS" ]
}

@test "valid workflow passes with scalar needs and scalar vault check" {
    mutate '.jobs.deploy.needs = "preflight-caller-contract" |
            .jobs.deploy.steps[0].with."extra-checks" = "vault"'
    run_contract
    assert_status_is 0
}

@test "malformed YAML fails closed" {
    printf '%s\n' '  malformed: [unterminated' >> "$WORKFLOW"
    assert_rejected "workflow"
}

@test "missing contract and deploy jobs are independently rejected" {
    mutate 'del(.jobs."preflight-caller-contract")'
    assert_rejected ".jobs.preflight-caller-contract" || return 1

    restore_fixture
    mutate 'del(.jobs.deploy)'
    assert_rejected ".jobs.deploy"
}

@test "workflow must keep an unfiltered pull_request admission trigger" {
    mutate 'del(.on.pull_request)'
    assert_rejected ".on.pull_request" || return 1

    restore_fixture
    mutate '.on.pull_request.paths = ["docs/**"]'
    assert_rejected ".on.pull_request"
}

@test "contract job has an exact capability-free shape" {
    mutate '.jobs."preflight-caller-contract".services.vault.image = "hashicorp/vault"'
    assert_rejected ".jobs.preflight-caller-contract.capabilities" || return 1

    restore_fixture
    mutate '.jobs."preflight-caller-contract".env.KEY = "${{ secrets.OPSBOT_API_KEY }}"'
    assert_rejected ".jobs.preflight-caller-contract.capabilities" || return 1

    restore_fixture
    mutate '.jobs."preflight-caller-contract".container = "ubuntu:latest"'
    assert_rejected ".jobs.preflight-caller-contract.capabilities" || return 1

    restore_fixture
    mutate '.jobs."preflight-caller-contract".if = "always()"'
    assert_rejected ".jobs.preflight-caller-contract.capabilities" || return 1

    restore_fixture
    mutate '.jobs."preflight-caller-contract".steps += [{"run":"docker ps && vault status && sudo broker"}]'
    assert_rejected ".jobs.preflight-caller-contract.steps"
}

@test "contract checkout is immutable, credential-minimal, and bound to workflow_sha" {
    mutate '.jobs."preflight-caller-contract".steps[0].uses = "actions/checkout@main"'
    assert_rejected ".jobs.preflight-caller-contract.steps.checkout" || return 1

    restore_fixture
    mutate '.jobs."preflight-caller-contract".steps[0].with."persist-credentials" = true'
    assert_rejected ".jobs.preflight-caller-contract.steps.checkout" || return 1

    restore_fixture
    mutate '.jobs."preflight-caller-contract".steps[0].with.ref = "${{ github.sha }}"'
    assert_rejected ".jobs.preflight-caller-contract.steps.checkout"
}

@test "contract action is unique, self-bound, and accepts no identity override" {
    mutate '.jobs."preflight-caller-contract".steps[1].uses = "Arcanada-one/datarim/.github/actions/preflight-caller-contract@main"'
    assert_rejected ".jobs.preflight-caller-contract.steps.contract" || return 1

    restore_fixture
    mutate '.jobs."preflight-caller-contract".steps[1].with."service-name" = "legal"'
    assert_rejected ".jobs.preflight-caller-contract.steps.contract" || return 1

    restore_fixture
    mutate '.jobs."preflight-caller-contract".steps += [.jobs."preflight-caller-contract".steps[1]]'
    assert_rejected ".jobs.preflight-caller-contract.steps"
}

@test "deploy must depend on the fixed contract job" {
    mutate '.jobs.deploy.needs = ["build"]'
    assert_rejected ".jobs.deploy.needs"
}

@test "deploy condition is anchored in the immutable consumer registry" {
    for bypass in 'always()' 'true' "needs.preflight-caller-contract.result == 'failure' || true"; do
        VALUE="$bypass" yq -i '.jobs.deploy.if = strenv(VALUE)' "$WORKFLOW"
        assert_rejected ".jobs.deploy.if" || return 1
        restore_fixture
    done
}

@test "deploy job cannot continue on error" {
    mutate '.jobs.deploy."continue-on-error" = true'
    assert_rejected ".jobs.deploy.continue-on-error"
}

@test "deploy VAULT_ADDR must map exactly to repository vars" {
    mutate 'del(.jobs.deploy.env.VAULT_ADDR)'
    assert_rejected ".jobs.deploy.env.VAULT_ADDR" || return 1

    for replacement in '' '${{ env.VAULT_ADDR }}' 'https://vault.invalid'; do
        restore_fixture
        VALUE="$replacement" yq -i '.jobs.deploy.env.VAULT_ADDR = strenv(VALUE)' "$WORKFLOW"
        assert_rejected ".jobs.deploy.env.VAULT_ADDR" || return 1
    done
}

@test "resolved Vault address rejects malformed values without disclosure" {
    local unsafe
    for unsafe in '' 'ftp://vault.internal' 'https://:8200' 'https:///path' 'https://vault.internal:65536' 'https://vault.internal:99999' 'https://user:pass@vault.internal' 'https://vault.internal/path with-space'; do
        CALLER_VAULT_ADDR_OVERRIDE="$unsafe" run_contract
        if [ "$status" -ne 1 ]; then
            echo "unsafe Vault case was accepted: $unsafe" >&2
            return 1
        fi
        assert_output_has "vault-addr" || return 1
        if [ -n "$unsafe" ] && [[ "$output" == *"$unsafe"* ]]; then
            echo "unsafe Vault value was disclosed" >&2
            return 1
        fi
    done

    CALLER_VAULT_ADDR_OVERRIDE="https://vault.internal:65535" run_contract
    assert_status_is 0
}

@test "preflight action is globally unique and pinned to the validator revision" {
    for pin in main abcdef0 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; do
        mutate ".jobs.deploy.steps[0].uses = \"Arcanada-one/datarim/.github/actions/preflight-check@${pin}\""
        assert_rejected ".jobs.deploy.steps.uses" || return 1
        restore_fixture
    done

    mutate '.jobs.build.steps += [{"uses":"Arcanada-one/datarim/.github/actions/preflight-check@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]'
    assert_rejected ".jobs.deploy.steps.uses"
}

@test "preflight step cannot be conditional, fail-soft, or lose its fixed id" {
    mutate '.jobs.deploy.steps[0].if = "false"'
    assert_rejected ".jobs.deploy.steps.preflight-shape" || return 1

    restore_fixture
    mutate '.jobs.deploy.steps[0]."continue-on-error" = true'
    assert_rejected ".jobs.deploy.steps.preflight-shape" || return 1

    restore_fixture
    mutate '.jobs.deploy.steps[0].id = "other"'
    assert_rejected ".jobs.deploy.steps.id"
}

@test "preflight is first and later deploy steps cannot override failure propagation" {
    mutate '.jobs.deploy.steps = [.jobs.deploy.steps[1], .jobs.deploy.steps[0]]'
    assert_rejected ".jobs.deploy.steps.order" || return 1

    for bypass in 'always()' 'failure()' '!cancelled()' 'success() || true'; do
        restore_fixture
        VALUE="$bypass" yq -i '.jobs.deploy.steps[1].if = strenv(VALUE)' "$WORKFLOW"
        assert_rejected ".jobs.deploy.steps.if" || return 1
    done

    restore_fixture
    mutate '.jobs.deploy.steps[1]."continue-on-error" = true'
    assert_rejected ".jobs.deploy.steps.continue-on-error"
}

@test "extra-checks requires an exact vault line token" {
    for value in '' 'vaultish' 'time-skew'; do
        VALUE="$value" yq -i '.jobs.deploy.steps[0].with."extra-checks" = strenv(VALUE)' "$WORKFLOW"
        assert_rejected ".jobs.deploy.steps.with.extra-checks" || return 1
        restore_fixture
    done
}

@test "service identity and key name are bound by the immutable registry" {
    mutate '.jobs.deploy.steps[0].with."service-name" = "legal"'
    assert_rejected ".jobs.deploy.steps.with.service-name" || return 1

    restore_fixture
    mutate '.jobs.deploy.steps[0].with."ops-bot-agent" = "legal"'
    assert_rejected ".jobs.deploy.steps.with.ops-bot-agent" || return 1

    restore_fixture
    mutate '.jobs.deploy.steps[0].with."ops-bot-key" = "${{ secrets.NONEXISTENT_KEY }}"'
    assert_rejected ".jobs.deploy.steps.with.ops-bot-key"
}

@test "notification emission must be explicitly true" {
    for value in '' 'false'; do
        VALUE="$value" yq -i '.jobs.deploy.steps[0].with."ops-bot-emit" = strenv(VALUE)' "$WORKFLOW"
        assert_rejected ".jobs.deploy.steps.with.ops-bot-emit" || return 1
        restore_fixture
    done
}

@test "Ops Bot endpoint must be the explicit canonical URL" {
    local replacement
    for replacement in '' 'https://ops.arcanada.one/events' '${{ vars.OPSBOT_URL }}'; do
        VALUE="$replacement" yq -i '.jobs.deploy.steps[0].with."ops-bot-url" = strenv(VALUE)' "$WORKFLOW"
        assert_rejected ".jobs.deploy.steps.with.ops-bot-url" || return 1
        restore_fixture
    done
}

@test "unregistered legacy Legal wiring fails closed" {
    cp "$FIXTURES/legacy-legal.yml" "$WORKFLOW"
    CALLER_REPOSITORY_OVERRIDE="Arcanada-one/legal-arcana" run_contract
    assert_status_is 1 || return 1
    assert_output_has "registry.Arcanada-one/legal-arcana"
}

@test "runtime provenance independently rejects repository, ref, and path substitution" {
    CALLER_ACTION_REPOSITORY_OVERRIDE="evil/fork" run_contract
    assert_status_is 1 || return 1
    assert_output_has "action_repository" || return 1

    CALLER_ACTION_REF_OVERRIDE="main" run_contract
    assert_status_is 1 || return 1
    assert_output_has "action_ref" || return 1

    CALLER_WORKFLOW_REF_OVERRIDE="Arcanada-one/muneral/../../fixture.yml@refs/heads/main" run_contract
    assert_status_is 1 || return 1
    assert_output_has "workflow_ref"
}

@test "runtime provenance rejects a workflow changed after workflow_sha checkout" {
    printf '%s\n' '# post-checkout substitution' >> "$WORKFLOW"
    CALLER_SKIP_SYNC=true run_contract
    assert_status_is 1 || return 1
    assert_output_has "workflow"
}

@test "toolchain rejects an unpinned yq version" {
    local fake_bin="$BATS_TEST_TMPDIR/fake-bin"
    mkdir -p "$fake_bin"
    for version in v4.45.1 v4.44.30; do
        printf '%s\n' '#!/usr/bin/env bash' "echo \"yq version $version\"" > "$fake_bin/yq"
        chmod +x "$fake_bin/yq"
        CALLER_YQ_BIN_OVERRIDE="$fake_bin/yq" run_contract
        assert_status_is 1 || return 1
        assert_output_has "tool.yq" || return 1
    done
}
