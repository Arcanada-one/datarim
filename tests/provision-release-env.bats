#!/usr/bin/env bats
# provision-release-env.bats — idempotent GitHub deployment-environment
# provisioner with exact tag and branch deployment policies.
#
# TDD-red first. The GitHub API edge is injected via the GH_API_CMD hook so the
# test is deterministic and mocks only the boundary (gh), never the provisioning
# logic. The default safety contract is dry-run: no mutating call fires without
# --apply.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/provision-release-env.sh"
    WORK="$(mktemp -d)"
    # Mock gh: record every invocation (one line per call) to CALLS, echo a
    # canned body for the GET that reads back the current policy. Verbs that
    # mutate (PUT/POST/DELETE) only ever appear in CALLS under --apply.
    export GH_CALLS="$WORK/gh-calls.log"
    export GH_ENV_RESPONSE='{}'
    export GH_POLICIES_RESPONSE='{}'
    : > "$GH_CALLS"
    cat > "$WORK/gh" <<'MOCK'
#!/usr/bin/env bash
# Minimal gh-api stand-in. Logs argv plus any piped JSON body (so nested-object
# PUT/POST bodies are assertable), returns empty JSON object for reads.
line="$*"
read_stdin=0
previous=""
for argument in "$@"; do
    [ "$previous" = "--input" ] && [ "$argument" = "-" ] && read_stdin=1
    previous="$argument"
done
if [ "$read_stdin" -eq 1 ]; then
    body="$(cat)"
    [ -n "$body" ] && line="$line ${body}"
fi
printf '%s\n' "$line" >> "$GH_CALLS"
if [[ "$line" != *" -X "* && "$line" == *"deployment-branch-policies"* ]]; then
    printf '%s\n' "$GH_POLICIES_RESPONSE"
elif [[ "$line" != *" -X "* && "$line" == *"/environments/"* ]]; then
    printf '%s\n' "$GH_ENV_RESPONSE"
else
    printf '{}\n'
fi
MOCK
    chmod +x "$WORK/gh"
    export GH_API_CMD="$WORK/gh"
}

teardown() { rm -rf "$WORK"; }

_run() { run "$SCRIPT" "$@"; }
_calls() { cat "$GH_CALLS"; }

# --- usage / validation -----------------------------------------------------

@test "missing --repo -> usage error exit 2" {
    _run --env release-auto
    [ "$status" -eq 2 ]
    [[ "$output" == *"--repo"* ]]
}

@test "missing --env -> usage error exit 2" {
    _run --repo Arcanada-one/coworker
    [ "$status" -eq 2 ]
    [[ "$output" == *"--env"* ]]
}

@test "malformed --repo (no owner/name slash) -> usage error exit 2" {
    _run --repo coworker --env release-auto
    [ "$status" -eq 2 ]
}

@test "invalid --env (path traversal) -> usage error exit 2" {
    _run --repo Arcanada-one/coworker --env "../evil"
    [ "$status" -eq 2 ]
}

@test "unsafe branch policy is rejected before API mutation" {
    _run --repo Arcanada-one/coworker --env release-auto --branch-policy 'main\"}'
    [ "$status" -eq 2 ]
    [ ! -s "$GH_CALLS" ]
}

# --- dry-run default (no mutation) ------------------------------------------

@test "default is dry-run: NO mutating gh call fires" {
    _run --repo Arcanada-one/coworker --env release-auto
    [ "$status" -eq 0 ]
    run grep -E -- '-X (PUT|POST|DELETE)' "$GH_CALLS"
    [ "$status" -ne 0 ]   # no mutating verb recorded
}

@test "read-only policy GET does not consume inherited open stdin" {
    local stdin_fifo="$WORK/open-stdin"
    local writer_pid
    mkfifo "$stdin_fifo"
    (exec 3>"$stdin_fifo"; sleep 10) &
    writer_pid=$!

    run timeout --signal=TERM --kill-after=1s 2s \
        "$SCRIPT" --repo Arcanada-one/coworker --env release-auto \
        < "$stdin_fifo"

    kill "$writer_pid" 2>/dev/null || true
    wait "$writer_pid" 2>/dev/null || true
    [ "$status" -eq 0 ]
}

@test "dry-run prints the planned PUT plus tag and branch policy POSTs" {
    _run --repo Arcanada-one/coworker --env release-auto
    [ "$status" -eq 0 ]
    [[ "$output" == *"environments/release-auto"* ]]
    [[ "$output" == *"deployment-branch-policies"* ]]
    [[ "$output" == *"v*"* ]]
    [[ "$output" == *"main"* ]]
    [[ "$output" == *'"type":"branch"'* ]]
}

# --- apply: environment + exact tag/branch policies -------------------------

@test "--apply PUTs the environment with custom_branch_policies=true" {
    _run --repo Arcanada-one/coworker --env release-auto --apply
    [ "$status" -eq 0 ]
    run grep -E -- '-X PUT .*environments/release-auto' "$GH_CALLS"
    [ "$status" -eq 0 ]
    run grep -- '"custom_branch_policies":true' "$GH_CALLS"
    [ "$status" -eq 0 ]
    run grep -- '"protected_branches":false' "$GH_CALLS"
    [ "$status" -eq 0 ]
}

@test "--apply POSTs the v* tag deployment-branch-policy" {
    _run --repo Arcanada-one/coworker --env release-auto --apply
    [ "$status" -eq 0 ]
    run grep -E -- '-X POST .*environments/release-auto/deployment-branch-policies' "$GH_CALLS"
    [ "$status" -eq 0 ]
    run grep -- '"type":"tag"' "$GH_CALLS"
    [ "$status" -eq 0 ]
}

@test "--apply POSTs the main branch deployment policy" {
    _run --repo Arcanada-one/coworker --env release-auto --apply
    [ "$status" -eq 0 ]
    run grep -- '"name":"main","type":"branch"' "$GH_CALLS"
    [ "$status" -eq 0 ]
}

@test "custom --tag-policy is honoured in the POST" {
    _run --repo Arcanada-one/coworker --env release-auto --apply --tag-policy 'release-v*'
    [ "$status" -eq 0 ]
    run grep -F -- 'release-v*' "$GH_CALLS"
    [ "$status" -eq 0 ]
}

@test "custom --branch-policy is honoured in the POST" {
    _run --repo Arcanada-one/coworker --env release-auto --apply --branch-policy 'release/*'
    [ "$status" -eq 0 ]
    run grep -F -- '"name":"release/*","type":"branch"' "$GH_CALLS"
    [ "$status" -eq 0 ]
}

# --- required_reviewers preservation (manual env) ---------------------------

@test "--reviewers adds a required_reviewers rule with the numeric id on the PUT" {
    _run --repo Arcanada-one/coworker --env release-manual --apply --reviewers User:24621879
    [ "$status" -eq 0 ]
    run grep -- '"required_reviewers":\[{"type":"User","id":24621879}\]' "$GH_CALLS"
    [ "$status" -eq 0 ]
}

@test "--reviewers rejects a slug (non-numeric id) -> usage error exit 2" {
    _run --repo Arcanada-one/coworker --env release-manual --apply --reviewers Team:security-reviewers
    [ "$status" -eq 2 ]
}

@test "without --reviewers no required_reviewers rule is sent for a new auto env" {
    _run --repo Arcanada-one/coworker --env release-auto --apply
    [ "$status" -eq 0 ]
    run grep -- 'required_reviewers' "$GH_CALLS"
    [ "$status" -ne 0 ]
}

@test "existing custom environment is not PUT and retains server-side protections" {
    export GH_ENV_RESPONSE='{"deployment_branch_policy":{"custom_branch_policies":true,"protected_branches":false},"protection_rules":[{"type":"required_reviewers","reviewers":[{"type":"User","reviewer":{"id":24621879}}]}]}'
    _run --repo Arcanada-one/coworker --env release-manual --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"preserving protection rules"* ]]
    run grep -E -- '-X PUT .*environments/release-manual' "$GH_CALLS"
    [ "$status" -ne 0 ]
}

@test "required reviewers and timer survive a necessary environment PUT" {
    export GH_ENV_RESPONSE='{"deployment_branch_policy":{"custom_branch_policies":false,"protected_branches":true},"prevent_self_review":true,"protection_rules":[{"type":"required_reviewers","reviewers":[{"type":"User","reviewer":{"id":24621879}}]},{"type":"wait_timer","wait_timer":12}]}'
    _run --repo Arcanada-one/coworker --env release-manual --apply
    [ "$status" -eq 0 ]
    run grep -- '"required_reviewers":\[{"type":"User","id":24621879}\]' "$GH_CALLS"
    [ "$status" -eq 0 ]
    run grep -- '"wait_timer":12' "$GH_CALLS"
    [ "$status" -eq 0 ]
    run grep -- '"prevent_self_review":true' "$GH_CALLS"
    [ "$status" -eq 0 ]
}

# --- idempotency and exact tuple matching ------------------------------------

@test "--apply reads environment and policies before mutation" {
    _run --repo Arcanada-one/coworker --env release-auto --apply
    [ "$status" -eq 0 ]
    run sed -n '1p' "$GH_CALLS"
    [[ "$output" == *"environments/release-auto"* ]]
    [[ "$output" != *"deployment-branch-policies"* ]]
    run sed -n '2p' "$GH_CALLS"
    [[ "$output" == *"deployment-branch-policies"* ]]
}

@test "existing exact policies suppress duplicate POSTs" {
    export GH_ENV_RESPONSE='{"deployment_branch_policy":{"custom_branch_policies":true,"protected_branches":false}}'
    export GH_POLICIES_RESPONSE='{"branch_policies":[{"name":"v*","type":"tag"},{"name":"main","type":"branch"}]}'
    _run --repo Arcanada-one/coworker --env release-auto --apply
    [ "$status" -eq 0 ]
    run grep -E -- '-X POST' "$GH_CALLS"
    [ "$status" -ne 0 ]
}

@test "name/type inversion does not pass exact policy matching" {
    export GH_ENV_RESPONSE='{"deployment_branch_policy":{"custom_branch_policies":true,"protected_branches":false}}'
    export GH_POLICIES_RESPONSE='{"branch_policies":[{"name":"v*","type":"branch"},{"name":"main","type":"tag"}]}'
    _run --repo Arcanada-one/coworker --env release-auto --apply
    [ "$status" -eq 0 ]
    run grep -c -E -- '-X POST .*deployment-branch-policies' "$GH_CALLS"
    [ "$status" -eq 0 ]
    [ "$output" -eq 2 ]
}
