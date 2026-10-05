#!/usr/bin/env bats

setup() {
    REPO="${ARTIFACT_TEST_SOURCE:-${BATS_TEST_DIRNAME}/..}"
    WORK="$(mktemp -d)"
    WORK="$(cd "$WORK" && pwd -P)"
    STATE="$WORK/datarim"
    DESC="$STATE/tasks/TEST-0001-task-description.md"
    mkdir -p "$STATE/tasks" "$STATE/prd" "$STATE/plans"
    cat > "$DESC" <<'EOF'
---
task_id: TEST-0001
complexity: L3
prd: prd/PRD-TEST-0001-v2.md
plan: plans/TEST-0001-plan-v3.md
---
- Evidence: V-AC-1 — independently recorded result
EOF
    cat > "$STATE/prd/PRD-TEST-0001-v2.md" <<'EOF'
---
task_id: TEST-0001
---
# Example requirements
**Complexity:** Level 3
#### D-REQ-01: use the explicitly selected document
- V-AC-1: correct artifact is validated
  Covers: D-REQ-01
EOF
    cat > "$STATE/plans/TEST-0001-plan-v3.md" <<'EOF'
---
task_id: TEST-0001
---
# Example plan
- Step 1: validate the selected artifact
  Verifies: V-AC-1
EOF
    cat > "$STATE/tasks/TEST-0001-expectations.md" <<'EOF'
---
task_id: TEST-0001
artifact: expectations
schema_version: 3
captured_at: 2026-10-05
captured_by: /dr-prd
agent: architect
parent_prd: ../prd/PRD-TEST-0001-v2.md
status: canonical
---
## Expectations
- **1. Validate the selected document.**
  - wish_id: selected-document
  - success_criterion: Check independent evidence.
  - linked_ac: V-AC-1
  - evidence_type: static
  - #### status_history
    - 2026-10-05 · /dr-qa · met · reason: Independent check recorded.
  - #### current_status
    - met
EOF
}

teardown() { rm -rf -- "$WORK"; }

resolve() {
    run bash -c 'source "$1/scripts/lib/task-artifact-path.sh" && task_artifact_path "$2" "$3" "$4"' _ "$REPO" "$STATE" "${2:-TEST-0001}" "$1"
}

rewrite_descriptor() { printf '%s\n' '---' "$@" '---' > "$DESC"; }

@test "expectations accept the exact selected versioned PRD parent" {
    run "$REPO/dev-tools/check-expectations-checklist.sh" --verify TEST-0001 --root "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *PASS* ]]
}

@test "spec lint validates selected versioned documents without legacy copies" {
    run "$REPO/dev-tools/dr-spec-lint.sh" --task TEST-0001 --root "$WORK" --stage plan --format json
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "trace includes requirements from the selected versioned PRD" {
    run "$REPO/dev-tools/dr-trace.sh" --task TEST-0001 --root "$WORK" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *D-REQ-01* ]]
}

@test "stage gate reports selected versioned artifacts" {
    run "$REPO/dev-tools/spec-graph-gate.sh" --task TEST-0001 --root "$WORK" --stage plan --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *PRD-TEST-0001-v2.md* ]]
    [[ "$output" == *TEST-0001-plan-v3.md* ]]
}

@test "selected PRD graph errors remain fatal even with a clean legacy copy" {
    cp "$STATE/prd/PRD-TEST-0001-v2.md" "$STATE/prd/PRD-TEST-0001.md"
    sed -i.bak 's/Covers: D-REQ-01/Covers: D-REQ-99/' "$STATE/prd/PRD-TEST-0001-v2.md"
    run "$REPO/dev-tools/dr-spec-lint.sh" --task TEST-0001 --root "$WORK" --stage plan --format json
    [ "$status" -eq 1 ]
    [[ "$output" == *D-REQ-99* ]]
}

@test "expectations reject a stale parent when a different revision is selected" {
    sed -i.bak 's@../prd/PRD-TEST-0001-v2.md@../prd/PRD-TEST-0001.md@' "$STATE/tasks/TEST-0001-expectations.md"
    run "$REPO/dev-tools/check-expectations-checklist.sh" --task TEST-0001 --root "$WORK"
    [ "$status" -eq 1 ]
    [[ "$output" == *parent_prd* ]]
    run "$REPO/dev-tools/check-expectations-checklist.sh" --verify TEST-0001 --root "$WORK"
    [ "$status" -eq 1 ]
    [[ "$output" == *BLOCKED* ]]
}

@test "undefined pointers retain legacy defaults without guessing newest revision" {
    rewrite_descriptor 'task_id: TEST-0001' 'prd: null' 'plan: null'
    resolve prd
    [ "$status" -eq 0 ]
    [ "$output" = "$STATE/prd/PRD-TEST-0001.md" ]
    resolve plan
    [ "$status" -eq 0 ]
    [ "$output" = "$STATE/plans/TEST-0001-plan.md" ]
}

@test "legacy descriptor without frontmatter retains fixed defaults" {
    printf '%s\n' '# Legacy task description' > "$DESC"
    resolve prd
    [ "$status" -eq 0 ]
    [ "$output" = "$STATE/prd/PRD-TEST-0001.md" ]
}

@test "quoted scalar pointers and matching id are accepted" {
    rewrite_descriptor 'id: "TEST-0001"' 'prd: "prd/PRD-TEST-0001-v2.md"'
    resolve prd
    [ "$status" -eq 0 ]
    [ "$output" = "$STATE/prd/PRD-TEST-0001-v2.md" ]
}

@test "invalid pointer shapes and cross-task references fail closed" {
    for pointer in '../prd/PRD-TEST-0001-v2.md' '/tmp/PRD-TEST-0001.md' 'prd/../prd/PRD-TEST-0001.md' 'prd/PRD-TEST-0002.md' 'plans/TEST-0001-plan-v3.md' 'prd/PRD-TEST-0001-v0.md' 'prd/PRD-TEST-0001-v02.md'; do
        rewrite_descriptor 'task_id: TEST-0001' "prd: $pointer"
        resolve prd
        [ "$status" -eq 2 ]
    [[ "$output" == *invalid*path* ]]
    done
}

@test "explicit missing revision refuses fallback to another existing revision" {
    rewrite_descriptor 'task_id: TEST-0001' 'prd: prd/PRD-TEST-0001-v4.md'
    resolve prd
    [ "$status" -eq 2 ]
    [[ "$output" == *missing* ]]
}

@test "duplicate nested non-scalar and unclosed descriptor fields are rejected" {
    rewrite_descriptor 'task_id: TEST-0001' 'prd: prd/PRD-TEST-0001-v2.md' 'prd: null'
    resolve prd
    [ "$status" -eq 2 ]
    [[ "$output" == *duplicate* ]]
    rewrite_descriptor 'task_id: TEST-0001' 'metadata:' '  prd: prd/PRD-TEST-0001-v2.md'
    resolve prd
    [ "$status" -eq 2 ]
    [[ "$output" == *top-level* ]]
    rewrite_descriptor 'task_id: TEST-0001' 'prd: |' '  prd/PRD-TEST-0001-v2.md'
    resolve prd
    [ "$status" -eq 2 ]
    [[ "$output" == *scalar* ]]
    printf '%s\n' '---' 'task_id: TEST-0001' > "$DESC"
    resolve prd
    [ "$status" -eq 2 ]
    [[ "$output" == *not*closed* ]]
}

@test "explicit selection requires matching descriptor and artifact identities" {
    rewrite_descriptor 'prd: prd/PRD-TEST-0001-v2.md'
    resolve prd
    [ "$status" -eq 2 ]
    [[ "$output" == *identity* ]]
    rewrite_descriptor 'task_id: TEST-0002' 'prd: prd/PRD-TEST-0001-v2.md'
    resolve prd
    [ "$status" -eq 2 ]
    [[ "$output" == *must*equal* ]]
    rewrite_descriptor 'task_id: TEST-0001' 'prd: prd/PRD-TEST-0001-v2.md'
    sed -i.bak 's/task_id: TEST-0001/task_id: TEST-0002/' "$STATE/prd/PRD-TEST-0001-v2.md"
    resolve prd
    [ "$status" -eq 2 ]
    [[ "$output" == *must*equal* ]]
}

@test "symlink descriptors directories and selected artifacts are rejected" {
    mv "$DESC" "$WORK/descriptor.md"
    ln -s "$WORK/descriptor.md" "$DESC"
    resolve prd
    [ "$status" -eq 2 ]
    [[ "$output" == *symlink* ]]
    rm "$DESC"
    mv "$WORK/descriptor.md" "$DESC"
    mv "$STATE/prd" "$WORK/prd"
    ln -s "$WORK/prd" "$STATE/prd"
    resolve prd
    [ "$status" -eq 2 ]
    [[ "$output" == *symlink* ]]
    rm "$STATE/prd"
    mv "$WORK/prd" "$STATE/prd"
    mv "$STATE/prd/PRD-TEST-0001-v2.md" "$WORK/prd.md"
    ln -s "$WORK/prd.md" "$STATE/prd/PRD-TEST-0001-v2.md"
    resolve prd
    [ "$status" -eq 2 ]
    [[ "$output" == *symlink* ]]
}

@test "invalid task identifiers and artifact kinds are rejected" {
    resolve prd '../TEST-0001'
    [ "$status" -eq 2 ]
    [[ "$output" == *invalid*task* ]]
    resolve unknown
    [ "$status" -eq 2 ]
    [[ "$output" == *invalid*kind* ]]
}

@test "malformed unrelated flat metadata cannot authorize artifact selection" {
    rewrite_descriptor 'task_id: TEST-0001' 'prd: prd/PRD-TEST-0001-v2.md' 'related: [TEST-0002'
    resolve prd
    [ "$status" -eq 2 ]
    [[ "$output" == *flow*list* ]]
    rewrite_descriptor 'task_id: TEST-0001' 'prd: prd/PRD-TEST-0001-v2.md' 'title: "unclosed'
    resolve prd
    [ "$status" -eq 2 ]
    [[ "$output" == *unclosed* ]]
}

@test "trusted ancestor aliases resolve to the same physical state boundary" {
    mkdir "$WORK/alias-parent"
    ln -s "$WORK" "$WORK/alias-parent/alias"
    STATE="$WORK/alias-parent/alias/datarim"
    resolve prd
    [ "$status" -eq 0 ]
    [ "$output" = "$WORK/datarim/prd/PRD-TEST-0001-v2.md" ]
}

@test "valid closed related-ID lists preserve selected scalar fields" {
    rewrite_descriptor 'id: TEST-0001' 'related: [TEST-0002, TEST-0003]' 'prd: prd/PRD-TEST-0001-v2.md'
    resolve prd
    [ "$status" -eq 0 ]
    [ "$output" = "$STATE/prd/PRD-TEST-0001-v2.md" ]
}

@test "compound task identities select only their own versioned artifacts" {
    mv "$DESC" "$STATE/tasks/TEST-0001-followup-task-description.md"
    DESC="$STATE/tasks/TEST-0001-followup-task-description.md"
    sed -i.bak 's/TEST-0001/TEST-0001-followup/g' "$DESC"
    mv "$STATE/prd/PRD-TEST-0001-v2.md" "$STATE/prd/PRD-TEST-0001-followup-v2.md"
    sed -i.bak 's/TEST-0001/TEST-0001-followup/g' "$STATE/prd/PRD-TEST-0001-followup-v2.md"
    resolve prd TEST-0001-followup
    [ "$status" -eq 0 ]
    [ "$output" = "$STATE/prd/PRD-TEST-0001-followup-v2.md" ]
}

@test "verification floor checks the selected versioned-only requirements" {
    run "$REPO/dev-tools/dr-verify-floor.sh" --task TEST-0001 --workspace "$WORK" --stage plan
    [ "$status" -eq 0 ]
    [[ "$output" == *scanning*PRD-TEST-0001-v2.md* ]]
    sed -i.bak 's/Covers: D-REQ-01/Covers: D-REQ-99/' "$STATE/prd/PRD-TEST-0001-v2.md"
    run "$REPO/dev-tools/dr-verify-floor.sh" --task TEST-0001 --workspace "$WORK" --stage plan
    [ "$status" -ge 1 ]
    [[ "$output" == *PRD-TEST-0001-v2.md* ]]
    [[ "$output" == *D-REQ-99* ]]
}

@test "legacy and selected scalar comments retain safe YAML semantics" {
    rewrite_descriptor 'id: TEST-0001 # identity annotation' 'complexity: L2' 'title: Legacy task # explanatory annotation' 'prd: null # no dedicated PRD' 'plan: null'
    resolve prd
    [ "$status" -eq 0 ]
    [ "$output" = "$STATE/prd/PRD-TEST-0001.md" ]
    run "$REPO/dev-tools/spec-graph-gate.sh" --task TEST-0001 --root "$WORK" --stage plan --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *skip* ]]
    rewrite_descriptor 'id: "TEST-0001" # identity annotation' 'title: "A # literal" # annotation' 'prd: "prd/PRD-TEST-0001-v2.md" # selected revision'
    resolve prd
    [ "$status" -eq 0 ]
    [ "$output" = "$STATE/prd/PRD-TEST-0001-v2.md" ]
    rewrite_descriptor "id: 'TEST-0001' # identity annotation" "title: 'A # literal' # annotation" "prd: 'prd/PRD-TEST-0001-v2.md' # selected revision"
    resolve prd
    [ "$status" -eq 0 ]
    [ "$output" = "$STATE/prd/PRD-TEST-0001-v2.md" ]
}

@test "selected document identities retain safe scalar and comment syntax" {
    sed -i.bak 's/task_id: TEST-0001/task_id: TEST-0001 # task identity annotation/' "$STATE/prd/PRD-TEST-0001-v2.md"
    sed -i.bak 's/task_id: TEST-0001/task_id: "TEST-0001" # task identity annotation/' "$STATE/plans/TEST-0001-plan-v3.md"
    resolve prd
    [ "$status" -eq 0 ]
    [ "$output" = "$STATE/prd/PRD-TEST-0001-v2.md" ]
    resolve plan
    [ "$status" -eq 0 ]
    [ "$output" = "$STATE/plans/TEST-0001-plan-v3.md" ]
    run "$REPO/dev-tools/dr-spec-lint.sh" --task TEST-0001 --root "$WORK" --stage plan --format json
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
