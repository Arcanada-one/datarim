#!/usr/bin/env bats

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../spec-graph-gate.sh"
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/datarim/prd" "$WORK/datarim/plans" "$WORK/datarim/tasks"
}

write_fixture() {
    cat >"$WORK/datarim/prd/PRD-GT-0001.md" <<'EOF'
# PRD: Gate
**Complexity:** Level 3

## Requirements (D-REQ)

#### D-REQ-01: automatic validation

## Success Criteria

- V-AC-1: graph is automatic
  Covers: D-REQ-01
EOF
    cat >"$WORK/datarim/plans/GT-0001-plan.md" <<'EOF'
# Plan
- Step 1: wire the graph
  Verifies: V-AC-1
EOF
    cat >"$WORK/datarim/tasks/GT-0001-task-description.md" <<'EOF'
## Implementation Notes
- Evidence: V-AC-1 — bats dev-tools/tests/spec-graph-gate.bats
EOF
    cat >"$WORK/datarim/tasks/GT-0001-expectations.md" <<'EOF'
- **1. Automatic graph.**
  - wish_id: automatic-graph
  - Связанный AC из PRD: V-AC-1
  - #### Текущий статус
    - pending
EOF
}

write_customer_prework_fixture() {
    write_fixture
    cat >>"$WORK/datarim/tasks/GT-0001-expectations.md" <<'EOF'
  - customer_derived: true
  - requirement_id: req-0001
  - surface_class: VISITOR_VISIBLE
  - visitor_visible: true
  - delivery_receipt: datarim/receipts/GT-0001-customer-delivery.yaml
EOF
    sed -i.bak '1i\---\nschema_version: 4\n---' \
        "$WORK/datarim/tasks/GT-0001-expectations.md"
    cat >"$WORK/datarim/tasks/GT-0001-customer-requirements.yaml" <<'EOF'
requirements:
  req-0001:
    acceptance:
      knowledge_selection:
        roles: [{id: reviewer}]
        skills: [{id: customer-delivery}]
        blueprints: [{id: delivery-blueprint}]
        constraints: [{id: prework}]
        policies: [{id: delivery-policy}]
        success_criteria: [{id: live-result}]
EOF
    mkdir -p "$WORK/datarim/receipts"
    cat >"$WORK/datarim/receipts/GT-0001-customer-delivery.yaml" <<'EOF'
requirements:
  req-0001:
    coverage_status: NOT_MET
    missing_edges:
      - implementation_delta
      - red_green
      - merged_revision
      - deployed_revision
      - live_evidence
      - customer_disposition
    coverage_chain:
      requirement:
        requirement_id: req-0001
      selected_knowledge:
        roles:
          - id: reviewer
            revision: "1"
            digest: sha256:1111111111111111111111111111111111111111111111111111111111111111
            selected_at: "2026-01-02T09:10:00Z"
            selected_before_implementation: true
            immutable: true
        skills:
          - id: customer-delivery
            revision: "1"
            digest: sha256:2222222222222222222222222222222222222222222222222222222222222222
            selected_at: "2026-01-02T09:11:00Z"
            selected_before_implementation: true
            immutable: true
        blueprints:
          - id: delivery-blueprint
            revision: "1"
            digest: sha256:3333333333333333333333333333333333333333333333333333333333333333
            selected_at: "2026-01-02T09:12:00Z"
            selected_before_implementation: true
            immutable: true
        constraints:
          - id: prework
            revision: "1"
            digest: sha256:4444444444444444444444444444444444444444444444444444444444444444
            selected_at: "2026-01-02T09:13:00Z"
            selected_before_implementation: true
            immutable: true
        policies:
          - id: delivery-policy
            revision: "1"
            digest: sha256:5555555555555555555555555555555555555555555555555555555555555555
            selected_at: "2026-01-02T09:14:00Z"
            selected_before_implementation: true
            immutable: true
        success_criteria:
          - id: live-result
            revision: "1"
            digest: sha256:6666666666666666666666666666666666666666666666666666666666666666
            selected_at: "2026-01-02T09:15:00Z"
            selected_before_implementation: true
            immutable: true
EOF
    cp "$WORK/datarim/receipts/GT-0001-customer-delivery.yaml" \
        "$WORK/datarim/tasks/GT-0001-customer-requirements.yaml"
    sed -i.bak 's/^      selected_knowledge:/      knowledge_selection:/' \
        "$WORK/datarim/tasks/GT-0001-customer-requirements.yaml"
}

@test "L3 defaults to advisory and emits evaluated artifact manifest" {
    write_fixture
    run "$SCRIPT" --task GT-0001 --stage qa --root "$WORK" --format json
    [ "$status" -eq 0 ] \
      && printf '%s\n' "$output" | grep -qF '"mode":"advisory"' \
      && printf '%s\n' "$output" | grep -qF '"evaluated_artifacts"'
}

@test "hard plan stage rejects missing explicit Verifies marker" {
    write_fixture
    sed -i.bak '/Verifies:/d' "$WORK/datarim/plans/GT-0001-plan.md"
    run env DATARIM_SPEC_GRAPH_MODE=hard "$SCRIPT" \
        --task GT-0001 --stage plan --root "$WORK" --format json
    [ "$status" -eq 1 ]
}

@test "do stage stays advisory in hard mode when evidence is missing" {
    write_fixture
    sed -i.bak '/Evidence:/d' "$WORK/datarim/tasks/GT-0001-task-description.md"
    run env DATARIM_SPEC_GRAPH_MODE=hard "$SCRIPT" \
        --task GT-0001 --stage do --root "$WORK" --format json
    [ "$status" -eq 0 ] \
      && printf '%s\n' "$output" | grep -qF '"decision":"advisory"'
}

@test "missing plan at plan stage is fail-closed exit 2" {
    write_fixture
    rm "$WORK/datarim/plans/GT-0001-plan.md"
    run "$SCRIPT" --task GT-0001 --stage plan --root "$WORK" --format json
    [ "$status" -eq 2 ]
}

@test "L1 task without PRD skips from task-description complexity" {
    cat >"$WORK/datarim/tasks/GT-0002-task-description.md" <<'EOF'
---
task_id: GT-0002
complexity: L1
---
EOF
    run "$SCRIPT" --task GT-0002 --stage do --root "$WORK" --format json
    [ "$status" -eq 0 ] \
      && printf '%s\n' "$output" | grep -qF '"decision":"skip"'
}

@test "L2 task without PRD skips because no graph is expected" {
    cat >"$WORK/datarim/tasks/GT-0003-task-description.md" <<'EOF'
---
task_id: GT-0003
complexity: L2
---
EOF
    run "$SCRIPT" --task GT-0003 --stage plan --root "$WORK" --format json
    [ "$status" -eq 0 ] \
      && printf '%s\n' "$output" | grep -qF '"decision":"skip"'
}

@test "invalid override text cannot suppress a hard completeness failure" {
    write_fixture
    sed -i.bak 's/    - pending/    - missed/' \
        "$WORK/datarim/tasks/GT-0001-expectations.md"
    sed -i.bak '/missed/i\  - override: nope\n  - override_by: operator' \
        "$WORK/datarim/tasks/GT-0001-expectations.md"
    sed -i.bak '/Verifies:/d' "$WORK/datarim/plans/GT-0001-plan.md"
    run env DATARIM_SPEC_GRAPH_MODE=hard "$SCRIPT" \
        --task GT-0001 --stage plan --root "$WORK" --format json
    [ "$status" -eq 1 ] \
      && printf '%s\n' "$output" | grep -qF 'no explicit plan binding'
}

@test "valid operator override excludes a partial wish from hard completeness" {
    write_fixture
    sed -i.bak 's/    - pending/    - partial/' \
        "$WORK/datarim/tasks/GT-0001-expectations.md"
    sed -i.bak '/partial/i\  - override: operator accepted this deferral\n  - override_by: operator' \
        "$WORK/datarim/tasks/GT-0001-expectations.md"
    sed -i.bak '/Verifies:/d' "$WORK/datarim/plans/GT-0001-plan.md"
    run env DATARIM_SPEC_GRAPH_MODE=hard "$SCRIPT" \
        --task GT-0001 --stage plan --root "$WORK" --format json
    [ "$status" -eq 0 ] \
      && ! printf '%s\n' "$output" | grep -qF '"check_name":"graph-complete-l3"'
}

@test "retrospective verify accepts legacy L3 task without expectations" {
    write_fixture
    rm "$WORK/datarim/tasks/GT-0001-expectations.md"
    run env DATARIM_SPEC_GRAPH_MODE=hard "$SCRIPT" \
        --task GT-0001 --stage verify --root "$WORK" --format json
    [ "$status" -eq 0 ] \
      && printf '%s\n' "$output" | grep -qF '"decision":"clean"'
}

@test "customer do stage emits a ready pre-work graph without claiming closure" {
    write_customer_prework_fixture
    run "$SCRIPT" --task GT-0001 --stage do --root "$WORK" --format json
    [ "$status" -eq 0 ] \
      && printf '%s\n' "$output" | grep -qF '"prework_ready":true' \
      && printf '%s\n' "$output" | grep -qF '"closure_authority":"check-customer-delivery.sh"' \
      && printf '%s\n' "$output" | grep -qF '"from":"requirement:req-0001"' \
      && printf '%s\n' "$output" | grep -qF '"to":"vac:V-AC-1"'
}

@test "customer do stage blocks when the receipt lacks selected knowledge" {
    write_customer_prework_fixture
    sed -i.bak '/^      selected_knowledge:/,$d' \
        "$WORK/datarim/receipts/GT-0001-customer-delivery.yaml"
    run "$SCRIPT" --task GT-0001 --stage do --root "$WORK" --format json
    [ "$status" -eq 1 ] \
      && printf '%s\n' "$output" | grep -qF '"prework_ready":false'
}

@test "customer do stage cannot fail-open on an incomplete customer binding" {
    write_customer_prework_fixture
    sed -i.bak '/^  - requirement_id: req-0001$/d' \
        "$WORK/datarim/tasks/GT-0001-expectations.md"
    run "$SCRIPT" --task GT-0001 --stage do --root "$WORK" --format json
    [ "$status" -eq 1 ] \
      && printf '%s\n' "$output" | grep -qF 'missing_customer_binding:requirement_id'
}

@test "customer do stage blocks incomplete selected-knowledge pin metadata" {
    write_customer_prework_fixture
    sed -i.bak '/^            immutable: true$/d' \
        "$WORK/datarim/receipts/GT-0001-customer-delivery.yaml"
    run "$SCRIPT" --task GT-0001 --stage do --root "$WORK" --format json
    [ "$status" -eq 1 ] \
      && printf '%s\n' "$output" | grep -qF 'missing_knowledge_kind:req-0001:roles'
}

@test "customer do stage blocks incomplete issued-contract knowledge metadata" {
    write_customer_prework_fixture
    sed -i.bak '/^            revision: /d' \
        "$WORK/datarim/tasks/GT-0001-customer-requirements.yaml"
    run "$SCRIPT" --task GT-0001 --stage do --root "$WORK" --format json
    [ "$status" -eq 1 ] \
      && printf '%s\n' "$output" | grep -qF 'missing_requirement_knowledge_kind:req-0001:roles'
}

@test "spec graph inventory does not assume customer delivery closure authority" {
    write_customer_prework_fixture
    run env DATARIM_SPEC_GRAPH_MODE=hard "$SCRIPT" \
        --task GT-0001 --stage qa --root "$WORK" --format json
    [ "$status" -eq 0 ] \
      && printf '%s\n' "$output" | grep -qF '"closure_authority":"check-customer-delivery.sh"' \
      && printf '%s\n' "$output" | grep -qF '"missing_edges"'
}

# ===========================================================================
# TUNE-0473 (B): documented PRD-waiver skip. An L3/L4 follow-up task running
# WITHOUT its own PRD but carrying the canonical `**PRD waived:**` marker must
# SKIP with an explicit reason, not die with a usage-error (TUNE-0472
# compliance got a usage-error instead of a graph verdict). No marker + no PRD
# still dies (the waiver is documented, never a silent bypass).
# ===========================================================================

# L3 task with NO PRD file. Whether it skips or dies depends solely on the marker.
write_noprd_fixture() {
    mkdir -p "$WORK/datarim/prd" "$WORK/datarim/plans" "$WORK/datarim/tasks"
    cat >"$WORK/datarim/plans/GT-0009-plan.md" <<'EOF'
# Plan
- Step 1: implement the follow-up
  Verifies: V-AC-1
EOF
    cat >"$WORK/datarim/tasks/GT-0009-task-description.md" <<'EOF'
## Implementation Notes
- Evidence: V-AC-1 — bats
EOF
}

@test "TUNE-0473-B: L3 follow-up with **PRD waived:** marker SKIPs with reason (not usage-error)" {
    write_noprd_fixture
    # Record the canonical waiver marker on the mandated surface (tasks.md).
    printf '## GT-0009\n**PRD waived:** scoped follow-up of parent PRD-EX-0001, approved <30d, no new requirements.\n' \
        >"$WORK/datarim/tasks.md"
    run "$SCRIPT" --task GT-0009 --stage compliance --root "$WORK" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision":"skip"'* ]]
    [[ "$output" == *"documented PRD-waiver"* ]]
}

@test "TUNE-0473-B-neg: L3 task with NO PRD and NO waiver marker still usage-dies (exit 2)" {
    write_noprd_fixture
    # No tasks.md waiver marker anywhere.
    run "$SCRIPT" --task GT-0009 --stage compliance --root "$WORK" --format json
    [ "$status" -eq 2 ]
    [[ "$output" == *"required PRD missing"* ]] || [[ "$output" == *"PRD"* ]]
}
