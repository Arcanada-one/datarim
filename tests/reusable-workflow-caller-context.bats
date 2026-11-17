#!/usr/bin/env bats
# Regression: reusable (workflow_call) workflows run in the CALLER's checkout.
#
# Releases 4.12.0..4.12.3 shipped four reusable workflows whose steps ran
# `bash .github/scripts/workflow/<helper>.sh`. That path exists only in this
# repository, so every caller job exited 127 (No such file or directory).
#
# This suite reads only the checked-out working tree (no git refs). It
# discovers the reusable workflows from the files themselves, so a reusable
# workflow added later is covered without editing the suite.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WF_DIR="$ROOT/.github/workflows"
    SANDBOX="$(mktemp -d)"
    GOOD_REF="0123456789abcdef0123456789abcdef01234567"
}

teardown() {
    rm -rf "$SANDBOX"
}

# Print the path of every workflow that declares `workflow_call`.
reusable_workflows() {
    local f
    for f in "$WF_DIR"/*.yml; do
        if [ "$(yq -r '.on | has("workflow_call")' "$f")" = "true" ]; then
            printf '%s\n' "$f"
        fi
    done
}

@test "caller context: the four known reusable workflows are discovered" {
    run reusable_workflows
    [ "$status" -eq 0 ]
    for n in network-exposure-lint public-surface-lint reusable-security-audit token-health-probe; do
        [[ "$output" == *"/$n.yml"* ]] || {
            echo "reusable workflow not discovered: $n" >&2
            return 1
        }
    done
}

@test "caller context: no reusable workflow step runs a script under .github/scripts/" {
    local f bad=0 runs
    while IFS= read -r f; do
        runs="$(yq -r '.jobs[].steps[]? | .run // ""' "$f")"
        if grep -F '.github/scripts/' <<<"$runs" >/dev/null; then
            echo "caller-relative helper path in run step of $(basename "$f")" >&2
            bad=1
        fi
    done < <(reusable_workflows)
    [ "$bad" -eq 0 ]
}

@test "caller context: no reusable workflow step uses a local action path" {
    local f bad=0 uses
    while IFS= read -r f; do
        uses="$(yq -r '.jobs[].steps[]? | .uses // ""' "$f")"
        if grep -E '^\./' <<<"$uses" >/dev/null; then
            echo "local action path in uses step of $(basename "$f")" >&2
            bad=1
        fi
    done < <(reusable_workflows)
    [ "$bad" -eq 0 ]
}

@test "caller context: network-exposure ref step runs in a checkout without .github/scripts" {
    local wf="$WF_DIR/network-exposure-lint.yml" step
    step="$SANDBOX/step.sh"
    yq -r '.jobs.lint.steps[] | select(.name == "Validate immutable Datarim ref") | .run' "$wf" >"$step"
    [ -s "$step" ]
    # The caller checkout: an empty directory, no .github/scripts at all.
    mkdir "$SANDBOX/caller"
    [ ! -e "$SANDBOX/caller/.github/scripts" ]

    run env -C "$SANDBOX/caller" DATARIM_REF="$GOOD_REF" bash "$step"
    [ "$status" -eq 0 ]

    run env -C "$SANDBOX/caller" DATARIM_REF="main" bash "$step"
    [ "$status" -eq 1 ]
    [[ "$output" == *"40-hex"* ]]

    run env -C "$SANDBOX/caller" DATARIM_REF="${GOOD_REF^^}" bash "$step"
    [ "$status" -eq 1 ]
}

@test "caller context: every network-exposure run step executes without a helper from this repository" {
    # Syntax-check each extracted run step and confirm it names no helper
    # path that an empty caller checkout would lack.
    local wf="$WF_DIR/network-exposure-lint.yml" i n
    n="$(yq -r '.jobs.lint.steps | length' "$wf")"
    for ((i = 0; i < n; i++)); do
        yq -r ".jobs.lint.steps[$i].run // \"\"" "$wf" >"$SANDBOX/s$i.sh"
        [ -s "$SANDBOX/s$i.sh" ] || continue
        run bash -n "$SANDBOX/s$i.sh"
        [ "$status" -eq 0 ]
        ! grep -F '.github/scripts/' "$SANDBOX/s$i.sh"
    done
}

@test "caller context: every reusable workflow exposes runner_labels with the same default" {
    local f name runs_on default
    while IFS= read -r f; do
        name="$(basename "$f")"
        runs_on="$(yq -r '.jobs[]."runs-on"' "$f" | head -n1)"
        # shellcheck disable=SC2016
        [ "$runs_on" = '${{ fromJSON(inputs.runner_labels) }}' ] || {
            echo "$name runs-on is not fromJSON(inputs.runner_labels): $runs_on" >&2
            return 1
        }
        default="$(yq -r '.on.workflow_call.inputs.runner_labels.default' "$f")"
        [ "$default" = '["self-hosted","linux","ci-general"]' ] || {
            echo "$name runner_labels default mismatch: $default" >&2
            return 1
        }
    done < <(reusable_workflows)
}
