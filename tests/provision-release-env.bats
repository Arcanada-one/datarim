#!/usr/bin/env bats
# provision-release-env.bats — idempotent GitHub deployment-environment
# provisioner with a tag-aware deployment-branch-policy.
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
    : > "$GH_CALLS"
    cat > "$WORK/gh" <<'MOCK'
#!/usr/bin/env bash
# Minimal gh-api stand-in. Logs argv plus any piped JSON body (so nested-object
# PUT/POST bodies are assertable), returns empty JSON object for reads.
line="$*"
if [ ! -t 0 ]; then
    body="$(cat)"
    [ -n "$body" ] && line="$line ${body}"
fi
printf '%s\n' "$line" >> "$GH_CALLS"
# A GET on an existing environment returns a body; everything else: {}.
printf '{}\n'
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

# --- dry-run default (no mutation) ------------------------------------------

@test "default is dry-run: NO mutating gh call fires" {
    _run --repo Arcanada-one/coworker --env release-auto
    [ "$status" -eq 0 ]
    run grep -E -- '-X (PUT|POST|DELETE)' "$GH_CALLS"
    [ "$status" -ne 0 ]   # no mutating verb recorded
}

@test "dry-run prints the planned PUT environment + tag-policy POST" {
    _run --repo Arcanada-one/coworker --env release-auto
    [ "$status" -eq 0 ]
    [[ "$output" == *"environments/release-auto"* ]]
    [[ "$output" == *"deployment-branch-policies"* ]]
    [[ "$output" == *"v*"* ]]
}

# --- apply: environment + tag policy ----------------------------------------

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

@test "custom --tag-policy is honoured in the POST" {
    _run --repo Arcanada-one/coworker --env release-auto --apply --tag-policy 'release-v*'
    [ "$status" -eq 0 ]
    run grep -F -- 'release-v*' "$GH_CALLS"
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

@test "without --reviewers no required_reviewers rule is sent (auto env)" {
    _run --repo Arcanada-one/coworker --env release-auto --apply
    [ "$status" -eq 0 ]
    run grep -- 'required_reviewers' "$GH_CALLS"
    [ "$status" -ne 0 ]
}

# --- idempotency: re-running does not duplicate the tag policy ---------------

@test "--apply checks existing policies before POSTing (GET precedes POST)" {
    _run --repo Arcanada-one/coworker --env release-auto --apply
    [ "$status" -eq 0 ]
    # The first gh call must be a read of the existing branch policies.
    run head -n1 "$GH_CALLS"
    [[ "$output" == *"deployment-branch-policies"* ]] || [[ "$output" == *"environments/release-auto"* ]]
}
