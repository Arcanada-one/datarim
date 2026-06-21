#!/usr/bin/env bats

setup() {
    GATE="${BATS_TEST_DIRNAME}/../spec-graph-gate.sh"
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK/datarim/prd" "$WORK/datarim/plans" \
        "$WORK/datarim/tasks" "$WORK/datarim/qa" "$WORK/datarim/reports"
    cat >"$WORK/datarim/prd/PRD-AUTO-0001.md" <<'EOF'
# PRD: Automatic path
**Complexity:** Level 3

## Requirements (D-REQ)

#### D-REQ-01: automatic stage validation

## Success Criteria

- V-AC-1: normal pipeline stages validate the graph
  Covers: D-REQ-01
EOF
    cat >"$WORK/datarim/tasks/AUTO-0001-expectations.md" <<'EOF'
- **1. Automatic validation.**
  - wish_id: automatic-validation
  - Связанный AC из PRD: V-AC-1
  - #### Текущий статус
    - pending
EOF
    cat >"$WORK/datarim/plans/AUTO-0001-plan.md" <<'EOF'
# Plan
- Step 1: wire automatic validation
  Verifies: V-AC-1
EOF
    cat >"$WORK/datarim/tasks/AUTO-0001-task-description.md" <<'EOF'
## Implementation Notes
- Evidence: V-AC-1 — bats dev-tools/tests/spec-graph-auto-path.bats
EOF
}

@test "PRD hard stage validates only PRD-time graph edges" {
    run env DATARIM_SPEC_GRAPH_MODE=hard "$GATE" \
        --task AUTO-0001 --stage prd --root "$WORK" --format json
    [ "$status" -eq 0 ]
}

@test "plan hard stage rejects missing explicit Verifies edge" {
    sed -i.bak '/Verifies:/d' "$WORK/datarim/plans/AUTO-0001-plan.md"
    run env DATARIM_SPEC_GRAPH_MODE=hard "$GATE" \
        --task AUTO-0001 --stage plan --root "$WORK" --format json
    [ "$status" -eq 1 ]
}

@test "do hard mode remains advisory while Evidence is incomplete" {
    sed -i.bak '/Evidence:/d' "$WORK/datarim/tasks/AUTO-0001-task-description.md"
    run env DATARIM_SPEC_GRAPH_MODE=hard "$GATE" \
        --task AUTO-0001 --stage do --root "$WORK" --format json
    [ "$status" -eq 0 ] \
      && printf '%s\n' "$output" | grep -qF '"decision":"advisory"'
}

@test "QA hard stage rejects missing explicit Evidence edge" {
    sed -i.bak '/Evidence:/d' "$WORK/datarim/tasks/AUTO-0001-task-description.md"
    run env DATARIM_SPEC_GRAPH_MODE=hard "$GATE" \
        --task AUTO-0001 --stage qa --root "$WORK" --format json
    [ "$status" -eq 1 ]
}

@test "complete graph passes QA and compliance hard stages" {
    run env DATARIM_SPEC_GRAPH_MODE=hard "$GATE" \
        --task AUTO-0001 --stage qa --root "$WORK" --format json
    qa_status="$status"
    run env DATARIM_SPEC_GRAPH_MODE=hard "$GATE" \
        --task AUTO-0001 --stage compliance --root "$WORK" --format json
    [ "$qa_status" -eq 0 ] && [ "$status" -eq 0 ]
}
