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

@test "L3 plan stage still requires a dedicated plan file" {
    write_fixture
    rm "$WORK/datarim/plans/GT-0001-plan.md"
    run "$SCRIPT" --task GT-0001 --stage plan --root "$WORK" --format json
    [ "$status" -eq 2 ] \
      && [[ "$output" == *"required artifact missing"* ]] \
      && [[ "$output" == *"datarim/plans/GT-0001-plan.md"* ]]
}

@test "L2 plan stage validates the canonical embedded task-description plan" {
    cat >"$WORK/datarim/prd/PRD-GT-0004.md" <<'EOF'
# PRD: Embedded plan
**Complexity:** Level 2

## Requirements (D-REQ)

#### D-REQ-01: embedded plans are validated

## Success Criteria

- V-AC-1: embedded validation succeeds
  Covers: D-REQ-01
EOF
    cat >"$WORK/datarim/tasks/GT-0004-task-description.md" <<'EOF'
---
task_id: GT-0004
complexity: L2
plan: null
---

## Implementation Plan

- Step 1: validate the embedded plan
  Verifies: V-AC-1
EOF
    run "$SCRIPT" --task GT-0004 --stage plan --root "$WORK" --format json
    [ "$status" -eq 0 ] \
      && [[ "$output" == *'"decision":"clean"'* ]] \
      && [[ "$output" == *'datarim/tasks/GT-0004-task-description.md'* ]] \
      && [[ "$output" != *'datarim/plans/GT-0004-plan.md'* ]]
}

@test "explicit PRD L3 cannot be downgraded by stale L2 task metadata" {
    cat >"$WORK/datarim/prd/PRD-GT-0005.md" <<'EOF'
# PRD: L3 precedence
**Complexity:** Level 3

#### D-REQ-01: L3 storage remains dedicated

- V-AC-1: dedicated plan is required
  Covers: D-REQ-01
EOF
    cat >"$WORK/datarim/tasks/GT-0005-task-description.md" <<'EOF'
---
task_id: GT-0005
complexity: L2
---

## Implementation Plan

- Step 1: stale embedded plan
  Verifies: V-AC-1
EOF
    run "$SCRIPT" --task GT-0005 --stage plan --root "$WORK" --format json
    [ "$status" -eq 2 ] \
      && [[ "$output" == *"datarim/plans/GT-0005-plan.md"* ]]
}

@test "gate and linter share the L2 index fallback for embedded plans" {
    cat >"$WORK/datarim/prd/PRD-GT-0006.md" <<'EOF'
# PRD: Index fallback

#### D-REQ-01: fallback remains consistent

- V-AC-1: embedded validation succeeds
  Covers: D-REQ-01
EOF
    cat >"$WORK/datarim/tasks/GT-0006-task-description.md" <<'EOF'
---
task_id: GT-0006
plan: null
---

## Implementation Plan

- Step 1: validate the embedded plan
  Verifies: V-AC-1
EOF
    printf '%s\n' '- GT-0006 · in_progress · P2 · L2 · Index fallback fixture' \
      > "$WORK/datarim/tasks.md"
    run "$SCRIPT" --task GT-0006 --stage plan --root "$WORK" --format json
    [ "$status" -eq 0 ] \
      && [[ "$output" == *'"complexity":"L2"'* ]] \
      && [[ "$output" == *'"decision":"clean"'* ]]
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
