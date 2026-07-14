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
