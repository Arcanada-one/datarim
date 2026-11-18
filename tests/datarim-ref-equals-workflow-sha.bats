#!/usr/bin/env bats
# workspace#1063: reusable workflows that take datarim_ref must refuse when the
# executed checkout SHA differs from the called workflow SHA (job.workflow_sha).
#
# The step body is extracted from the workflow YAML and run under env only — no
# moving git refs, no network.

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WF_DIR="$ROOT/.github/workflows"
    SANDBOX="$(mktemp -d)"
    GOOD_REF="0123456789abcdef0123456789abcdef01234567"
    OTHER_REF="abcdef0123456789abcdef0123456789abcdef01"
}

teardown() {
    rm -rf "$SANDBOX"
}

extract_validate_step() {
    local wf="$1" job="$2" out="$3"
    yq -r ".jobs.${job}.steps[] | select(.name == \"Validate immutable Datarim ref\") | .run" "$wf" >"$out"
    [ -s "$out" ]
}

@test "network-exposure: validate step fails when datarim_ref != workflow_sha" {
    local step="$SANDBOX/nel.sh"
    extract_validate_step "$WF_DIR/network-exposure-lint.yml" lint "$step"
    run env DATARIM_REF="$GOOD_REF" WORKFLOW_SHA="$OTHER_REF" bash "$step"
    [ "$status" -eq 1 ]
    [[ "$output" == *"uses_and_ref_disagree"* ]]
}

@test "network-exposure: validate step passes when datarim_ref == workflow_sha" {
    local step="$SANDBOX/nel.sh"
    extract_validate_step "$WF_DIR/network-exposure-lint.yml" lint "$step"
    run env DATARIM_REF="$GOOD_REF" WORKFLOW_SHA="$GOOD_REF" bash "$step"
    [ "$status" -eq 0 ]
}

@test "public-surface: validate step fails when datarim_ref != workflow_sha" {
    local step="$SANDBOX/ps.sh"
    extract_validate_step "$WF_DIR/public-surface-lint.yml" lint "$step"
    run env DATARIM_REF="$GOOD_REF" WORKFLOW_SHA="$OTHER_REF" bash "$step"
    [ "$status" -eq 1 ]
    [[ "$output" == *"uses_and_ref_disagree"* ]]
}

@test "reusable-security-audit: validate step fails when datarim_ref != workflow_sha" {
    local step="$SANDBOX/sa.sh"
    extract_validate_step "$WF_DIR/reusable-security-audit.yml" audit "$step"
    run env DATARIM_REF="$GOOD_REF" WORKFLOW_SHA="$OTHER_REF" bash "$step"
    [ "$status" -eq 1 ]
    [[ "$output" == *"uses_and_ref_disagree"* ]]
}

@test "every datarim_ref reusable workflow wires WORKFLOW_SHA from job.workflow_sha" {
    local f
    for f in \
        "$WF_DIR/network-exposure-lint.yml" \
        "$WF_DIR/public-surface-lint.yml" \
        "$WF_DIR/reusable-security-audit.yml"
    do
        # shellcheck disable=SC2016
        grep -F 'WORKFLOW_SHA: ${{ job.workflow_sha }}' "$f" >/dev/null || {
            echo "missing WORKFLOW_SHA wiring in $(basename "$f")" >&2
            return 1
        }
        # Must not bind the caller-side github.workflow_sha (rev-core blocking).
        # shellcheck disable=SC2016
        if grep -F 'WORKFLOW_SHA: ${{ github.workflow_sha }}' "$f" >/dev/null; then
            echo "wrong context github.workflow_sha in $(basename "$f")" >&2
            return 1
        fi
        grep -F 'Validate immutable Datarim ref' "$f" >/dev/null || {
            echo "missing validate step in $(basename "$f")" >&2
            return 1
        }
    done
}
