#!/usr/bin/env bats
# Fork refuse on every self-hosted-default reusable (workflow_call) workflow.
#
# Reads only the checked-out working tree and committed fixtures under
# tests/fixtures/reusable-fork-deny/ — never a moving git ref.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WF_DIR="$ROOT/.github/workflows"
    FIX="$ROOT/tests/fixtures/reusable-fork-deny"
    # Canonical job-level if (GitHub expression precedence: && before ||).
    CANONICAL_IF="github.event_name != 'pull_request' && github.event_name != 'pull_request_target' || github.event.pull_request.head.repo.full_name == github.repository"
}

# Discover reusable workflows from files (no git refs).
reusable_workflows() {
    local f
    for f in "$WF_DIR"/*.yml; do
        if [ "$(yq -r '.on | has("workflow_call")' "$f")" = "true" ]; then
            printf '%s\n' "$f"
        fi
    done
}

# Evaluate the canonical fork-deny semantics against a fixture JSON.
# Exit 0 when the job would run; exit 1 when refused. Mirrors Actions &&/||.
fork_deny_allows() {
    local fixture="$1"
    local event_name repository head_full
    event_name="$(jq -r '.event_name' "$fixture")"
    repository="$(jq -r '.repository' "$fixture")"
    head_full="$(jq -r '.pull_request.head.repo.full_name // empty' "$fixture")"

    # (event != pull_request && event != pull_request_target) || head == repository
    if [ "$event_name" != "pull_request" ] && [ "$event_name" != "pull_request_target" ]; then
        return 0
    fi
    if [ "$head_full" = "$repository" ]; then
        return 0
    fi
    return 1
}

@test "fork deny: every reusable workflow job carries the canonical if" {
    local f job_if name default bad=0
    while IFS= read -r f; do
        name="$(basename "$f")"
        default="$(yq -r '.on.workflow_call.inputs.runner_labels.default // ""' "$f")"
        # Only guard workflows whose default runner labels are self-hosted.
        [[ "$default" == *self-hosted* ]] || continue
        job_if="$(yq -r '.jobs[].if // ""' "$f" | head -n1)"
        [ "$job_if" = "$CANONICAL_IF" ] || {
            echo "$name job if mismatch:" >&2
            echo "  got:  $job_if" >&2
            echo "  want: $CANONICAL_IF" >&2
            bad=1
        }
    done < <(reusable_workflows)
    [ "$bad" -eq 0 ]
}

@test "fork deny: fixture fork pull_request is refused" {
    run fork_deny_allows "$FIX/fork-pull-request.json"
    [ "$status" -eq 1 ]
    [ "$(jq -r '.expect_run' "$FIX/fork-pull-request.json")" = "false" ]
}

@test "fork deny: fixture same-repo pull_request still runs" {
    run fork_deny_allows "$FIX/same-repo-pull-request.json"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.expect_run' "$FIX/same-repo-pull-request.json")" = "true" ]
}

@test "fork deny: fixture fork pull_request_target is refused" {
    run fork_deny_allows "$FIX/fork-pull-request-target.json"
    [ "$status" -eq 1 ]
}

@test "fork deny: fixture push still runs" {
    run fork_deny_allows "$FIX/push.json"
    [ "$status" -eq 0 ]
}

@test "fork deny: every fixture expect_run matches evaluator" {
    local f expect
    for f in "$FIX"/*.json; do
        expect="$(jq -r '.expect_run' "$f")"
        if fork_deny_allows "$f"; then
            [ "$expect" = "true" ] || {
                echo "fixture $(basename "$f"): evaluator allowed but expect_run=$expect" >&2
                return 1
            }
        else
            [ "$expect" = "false" ] || {
                echo "fixture $(basename "$f"): evaluator refused but expect_run=$expect" >&2
                return 1
            }
        fi
    done
}

@test "fork deny: four known reusable workflows are covered" {
    local n covered=0
    for n in network-exposure-lint public-surface-lint reusable-security-audit token-health-probe; do
        [ -f "$WF_DIR/$n.yml" ] || {
            echo "missing workflow: $n" >&2
            return 1
        }
        grep -Fq "$CANONICAL_IF" "$WF_DIR/$n.yml" || {
            echo "missing fork deny if in $n.yml" >&2
            return 1
        }
        covered=$((covered + 1))
    done
    [ "$covered" -eq 4 ]
}
