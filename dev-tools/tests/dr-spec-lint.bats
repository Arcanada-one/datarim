#!/usr/bin/env bats
#
# bats spec for dev-tools/dr-spec-lint.sh (R1) — the deterministic spec-graph
# validator. Covers each named rule (positive + negative), the clean fixture,
# and the R3/R7 flag semantics (--advisory, --dry-run, --format json, exit 2).

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../dr-spec-lint.sh"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/datarim/prd" "$WORK/datarim/plans" "$WORK/datarim/tasks"
}

teardown() {
    rm -rf "$WORK"
}

# Write a clean, fully-linked L3 fixture for task EX-0001.
write_clean_fixture() {
    cat >"$WORK/datarim/prd/PRD-EX-0001.md" <<'EOF'
# PRD: Example
**Complexity:** Level 3

## Requirements (D-REQ)

#### D-REQ-01: the validator builds a graph

#### D-REQ-02: the validator emits json

## Success Criteria

- V-AC-1: graph is built
  Covers: D-REQ-01
- V-AC-2: json is emitted
  Covers: D-REQ-02
EOF
    cat >"$WORK/datarim/plans/EX-0001-plan.md" <<'EOF'
# Plan: Example
- Step 1: build the graph
  Verifies: V-AC-1
- Step 2: emit json
  Verifies: V-AC-2
EOF
    cat >"$WORK/datarim/tasks/EX-0001-task-description.md" <<'EOF'
# Implementation Notes

- Evidence: V-AC-1 — bats dev-tools/tests/dr-spec-lint.bats
- Evidence: V-AC-2 — bats dev-tools/tests/dr-spec-lint.bats
EOF
    cat >"$WORK/datarim/tasks/EX-0001-expectations.md" <<'EOF'
- **1. Build graph.**
  - wish_id: build-graph
  - Связанный AC из PRD: V-AC-1
  - #### Текущий статус
    - pending
- **2. Emit json.**
  - wish_id: emit-json
  - Связанный AC из PRD: V-AC-2
  - #### Текущий статус
    - pending
EOF
}

@test "clean fixture — exit 0" {
    write_clean_fixture
    run "$SCRIPT" --task EX-0001 --root "$WORK"
    [ "$status" -eq 0 ]
}

@test "dreq-id-format — bad slug flagged" {
    write_clean_fixture
    # corrupt one D-REQ to a single-digit id
    sed -i.bak 's/#### D-REQ-01:/#### D-REQ-1:/' "$WORK/datarim/prd/PRD-EX-0001.md"
    run "$SCRIPT" --task EX-0001 --root "$WORK" --format json
    [ "$status" -ne 0 ]
    [[ "$output" == *"dreq-id-format"* ]]
}

@test "dreq-id-unique — duplicate id flagged" {
    write_clean_fixture
    sed -i.bak 's/#### D-REQ-02:/#### D-REQ-01:/' "$WORK/datarim/prd/PRD-EX-0001.md"
    run "$SCRIPT" --task EX-0001 --root "$WORK" --format json
    [ "$status" -ne 0 ]
    [[ "$output" == *"dreq-id-unique"* ]]
}

@test "covers-resolves / dreq-dangling — dangling Covers flagged" {
    write_clean_fixture
    sed -i.bak 's/Covers: D-REQ-02/Covers: D-REQ-77/' "$WORK/datarim/prd/PRD-EX-0001.md"
    run "$SCRIPT" --task EX-0001 --root "$WORK" --format json
    [ "$status" -ne 0 ]
    [[ "$output" == *"dreq-dangling"* ]] || [[ "$output" == *"covers-resolves"* ]]
}

@test "dreq-orphan — requirement with no V-AC flagged" {
    write_clean_fixture
    # add a third D-REQ that nothing covers
    printf '\n#### D-REQ-03: orphaned requirement\n' >>"$WORK/datarim/prd/PRD-EX-0001.md"
    run "$SCRIPT" --task EX-0001 --root "$WORK" --format json
    [[ "$output" == *"dreq-orphan"* ]]
}

@test "vac-covers-present — V-AC missing Covers flagged" {
    write_clean_fixture
    # remove the Covers line of V-AC-2
    sed -i.bak '/Covers: D-REQ-02/d' "$WORK/datarim/prd/PRD-EX-0001.md"
    run "$SCRIPT" --task EX-0001 --root "$WORK" --format json
    [[ "$output" == *"vac-covers-present"* ]]
}

@test "--advisory — findings present but exit 0" {
    write_clean_fixture
    sed -i.bak 's/#### D-REQ-01:/#### D-REQ-1:/' "$WORK/datarim/prd/PRD-EX-0001.md"
    run "$SCRIPT" --task EX-0001 --root "$WORK" --format json --advisory
    [ "$status" -eq 0 ]
    [[ "$output" == *"dreq-id-format"* ]]
}

@test "--dry-run — builds graph, no findings, exit 0" {
    write_clean_fixture
    sed -i.bak 's/#### D-REQ-01:/#### D-REQ-1:/' "$WORK/datarim/prd/PRD-EX-0001.md"
    run "$SCRIPT" --task EX-0001 --root "$WORK" --format json --dry-run
    [ "$status" -eq 0 ]
    [ -z "$output" ] || [[ "$output" != *'"check_name"'* ]]
}

@test "--format json — valid JSONL on findings" {
    write_clean_fixture
    sed -i.bak 's/#### D-REQ-01:/#### D-REQ-1:/' "$WORK/datarim/prd/PRD-EX-0001.md"
    run "$SCRIPT" --task EX-0001 --root "$WORK" --format json
    printf '%s\n' "$output" | python3 -c 'import json,sys; [json.loads(l) for l in sys.stdin if l.strip()]'
}

@test "unknown flag — exit 2" {
    write_clean_fixture
    run "$SCRIPT" --task EX-0001 --root "$WORK" --bogus
    [ "$status" -eq 2 ]
}

@test "missing --task — exit 2" {
    run "$SCRIPT" --root "$WORK"
    [ "$status" -eq 2 ]
}

@test "nonexistent task artefacts — exit 2" {
    run "$SCRIPT" --task ZZ-9999 --root "$WORK"
    [ "$status" -eq 2 ]
}

@test "hard mode — exactly two findings exit 1, not reserved config exit 2" {
    write_clean_fixture
    sed -i.bak 's/Covers: D-REQ-02/Covers: D-REQ-77/' "$WORK/datarim/prd/PRD-EX-0001.md"
    run "$SCRIPT" --task EX-0001 --root "$WORK" --format json
    [ "$status" -eq 1 ]
}

@test "registry applies_to — L2 skips axis-separation rule" {
    write_clean_fixture
    sed -i.bak 's/Level 3/Level 2/' "$WORK/datarim/prd/PRD-EX-0001.md"
    sed -i.bak 's/graph is built/exit code and p99 threshold are verified/' "$WORK/datarim/prd/PRD-EX-0001.md"
    run "$SCRIPT" --task EX-0001 --root "$WORK" --format json --advisory
    ! printf '%s\n' "$output" | grep -qF '"check_name": "axis-separation"'
}

@test "graph-complete-l3 — every current wish needs a linked V-AC path" {
    write_clean_fixture
    sed -i.bak 's/Связанный AC из PRD: V-AC-2/Связанный AC из PRD: —/' "$WORK/datarim/tasks/EX-0001-expectations.md"
    run "$SCRIPT" --task EX-0001 --root "$WORK" --stage prd --format json --advisory
    printf '%s\n' "$output" | grep -qF '"check_name": "graph-complete-l3"'
}

@test "vac-binding-present — incidental V-AC prose is not a plan edge" {
    write_clean_fixture
    cat >"$WORK/datarim/plans/EX-0001-plan.md" <<'EOF'
# Plan: Example
The prose mentions V-AC-1 and V-AC-2 but declares no graph markers.
EOF
    run "$SCRIPT" --task EX-0001 --root "$WORK" --stage plan --format json --advisory
    printf '%s\n' "$output" | grep -qF '"check_name": "vac-binding-present"'
}

@test "graph-complete-l3 — QA requires explicit Evidence marker" {
    write_clean_fixture
    sed -i.bak '/Evidence: V-AC-2/d' "$WORK/datarim/tasks/EX-0001-task-description.md"
    run "$SCRIPT" --task EX-0001 --root "$WORK" --stage qa --format json --advisory
    printf '%s\n' "$output" | grep -qF '"check_name": "graph-complete-l3"'
}

@test "graph-complete-l3 — a wish-linked V-AC cannot borrow another V-AC Covers edge" {
    write_clean_fixture
    sed -i.bak '/Covers: D-REQ-02/d' "$WORK/datarim/prd/PRD-EX-0001.md"
    run "$SCRIPT" --task EX-0001 --root "$WORK" --stage prd --format json --advisory
    printf '%s\n' "$output" \
      | grep -F '"check_name": "graph-complete-l3"' \
      | grep -qF 'V-AC-2'
}
