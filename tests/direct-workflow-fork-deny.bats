#!/usr/bin/env bats
# Fork refuse on every self-hosted job in non-reusable workflows that are
# reachable from pull_request / pull_request_target / workflow_run / issue_comment.
#
# Reads only the checked-out working tree and committed fixtures under
# tests/fixtures/reusable-fork-deny/ — never a moving git ref.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WF_DIR="$ROOT/.github/workflows"
    FIX="$ROOT/tests/fixtures/reusable-fork-deny"
    # Same-repo PR form used by bats.yml / coworker / output-guard.
    CANONICAL_IF="github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository"
    GUARD_NEEDLE="pull_request.head.repo.full_name == github.repository"
}

# Evaluate the direct-workflow fork-deny semantics against a fixture JSON.
# Exit 0 when the job would run; exit 1 when refused.
fork_deny_allows() {
    local fixture="$1"
    local event_name repository head_full
    event_name="$(jq -r '.event_name' "$fixture")"
    repository="$(jq -r '.repository' "$fixture")"
    head_full="$(jq -r '.pull_request.head.repo.full_name // empty' "$fixture")"

    # event != pull_request || head == repository
    if [ "$event_name" != "pull_request" ]; then
        return 0
    fi
    if [ "$head_full" = "$repository" ]; then
        return 0
    fi
    return 1
}

job_is_self_hosted() {
    local wf="$1" job="$2"
    local runs matrix
    runs="$(yq -r ".jobs.\"$job\".\"runs-on\" // \"\"" "$wf")"
    matrix="$(yq -r ".jobs.\"$job\".strategy.matrix // \"\"" "$wf")"
    [[ "$runs" == *self-hosted* || "$matrix" == *self-hosted* ]]
}

workflow_has_risky_trigger() {
    local wf="$1"
    local on
    on="$(yq -o=json -I0 '.on' "$wf")"
    echo "$on" | jq -e '
      (type == "string" and (. == "pull_request" or . == "pull_request_target" or . == "workflow_run" or . == "issue_comment"))
      or (type == "array" and (map(. == "pull_request" or . == "pull_request_target" or . == "workflow_run" or . == "issue_comment") | any))
      or (type == "object" and (has("pull_request") or has("pull_request_target") or has("workflow_run") or has("issue_comment")))
    ' >/dev/null
}

workflow_is_reusable_only() {
    local wf="$1"
    # Skip pure workflow_call reusables (covered by reusable-workflow-fork-deny.bats).
    local keys
    keys="$(yq -r '.on | keys | .[]' "$wf" 2>/dev/null || true)"
    if [ -z "$keys" ]; then
        # on: workflow_call as scalar-ish
        [ "$(yq -r '.on | has("workflow_call")' "$wf")" = "true" ] && [ "$(yq -r '.on | keys | length' "$wf")" = "1" ]
        return $?
    fi
    local has_call=0 has_other=0
    local k
    while IFS= read -r k; do
        [ -z "$k" ] && continue
        if [ "$k" = "workflow_call" ]; then
            has_call=1
        else
            has_other=1
        fi
    done <<< "$keys"
    [ "$has_call" -eq 1 ] && [ "$has_other" -eq 0 ]
}

@test "fork deny: every risky self-hosted direct job carries head.repo guard" {
    local f job job_if bad=0
    for f in "$WF_DIR"/*.yml; do
        workflow_is_reusable_only "$f" && continue
        workflow_has_risky_trigger "$f" || continue
        while IFS= read -r job; do
            [ -z "$job" ] && continue
            job_is_self_hosted "$f" "$job" || continue
            job_if="$(yq -r ".jobs.\"$job\".if // \"\"" "$f")"
            echo "$job_if" | grep -Fq "$GUARD_NEEDLE" || {
                echo "$(basename "$f") job=$job missing fork deny (if=$job_if)" >&2
                bad=1
            }
        done < <(yq -r '.jobs | keys | .[]' "$f")
    done
    [ "$bad" -eq 0 ]
}

@test "fork deny: listed census jobs use canonical same-repo if (or AND with prior if)" {
    local bad=0
    local pair wf job job_if
    for pair in \
        "bats.yml:suites" \
        "bats.yml:customer-delivery-linux" \
        "dev-tools-lint.yml:bats-self-tests" \
        "dev-tools-lint.yml:linter-run" \
        "dev-tools-lint.yml:dr-auto-reassert-wiring" \
        "dev-tools-lint.yml:dr-auto-cross-runtime" \
        "dr-orchestrate-contract.yml:schemathesis" \
        "framework-gates.yml:component-counts" \
        "framework-gates.yml:version-consistency" \
        "framework-gates.yml:body-english" \
        "framework-gates.yml:release-ledger" \
        "framework-gates.yml:frontmatter-schema" \
        "framework-gates.yml:template-path-convention" \
        "framework-gates.yml:archive-landing" \
        "framework-gates.yml:human-reporting" \
        "framework-gates.yml:test-value-card" \
        "frontmatter-mirror.yml:mirror-drift" \
        "frontmatter-mirror.yml:self-tests" \
        "gate-token-registry-sync.yml:registry-sync-check" \
        "personal-id-lint.yml:personal-id-lint" \
        "sanity-dual-copy.yml:diff" \
        "security.yml:shellcheck" \
        "security.yml:shellcheck-extracted" \
        "security.yml:bandit" \
        "security.yml:bandit-extracted" \
        "security.yml:semgrep-sarif" \
        "security.yml:codeql-python" \
        "security.yml:gitleaks" \
        "security.yml:trufflehog" \
        "security.yml:actionlint" \
        "security.yml:zizmor" \
        "security.yml:osv-scanner" \
        "security.yml:regression-bats" \
        "security.yml:markdown-policy" \
        "security.yml:doc-refs" \
        "security.yml:task-id-gate"
    do
        wf="${pair%%:*}"
        job="${pair##*:}"
        job_if="$(yq -r ".jobs.\"$job\".if // \"\"" "$WF_DIR/$wf")"
        case "$job_if" in
            *"$GUARD_NEEDLE"*) ;;
            *)
                echo "$wf/$job missing needle: $job_if" >&2
                bad=1
                ;;
        esac
        # Pure new guards should match canonical exactly.
        if [ "$job_if" = "$CANONICAL_IF" ] || echo "$job_if" | grep -Fq "($CANONICAL_IF)"; then
            :
        elif echo "$job_if" | grep -Fq "$GUARD_NEEDLE"; then
            :
        else
            echo "$wf/$job unexpected if: $job_if" >&2
            bad=1
        fi
    done
    [ "$bad" -eq 0 ]
}

@test "fork deny: version-tag-parity keeps push gate AND fork refuse" {
    local job_if
    job_if="$(yq -r '.jobs."version-tag-parity".if // ""' "$WF_DIR/framework-gates.yml")"
    echo "$job_if" | grep -Fq "$GUARD_NEEDLE"
    echo "$job_if" | grep -Fq "github.event_name == 'push'"
}

@test "fork deny: fixture fork pull_request is refused" {
    run fork_deny_allows "$FIX/fork-pull-request.json"
    [ "$status" -eq 1 ]
}

@test "fork deny: fixture same-repo pull_request still runs" {
    run fork_deny_allows "$FIX/same-repo-pull-request.json"
    [ "$status" -eq 0 ]
}

@test "fork deny: fixture push still runs" {
    run fork_deny_allows "$FIX/push.json"
    [ "$status" -eq 0 ]
}
