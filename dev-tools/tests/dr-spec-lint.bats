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

@test "L2 resolves the embedded task-description as its canonical plan" {
    cat >"$WORK/datarim/tasks/EX-0003-task-description.md" <<'EOF'
---
task_id: EX-0003
complexity: L2
plan: null
---

## Requirements (D-REQ)

#### D-REQ-01: embedded plans are linted

## Success Criteria

- V-AC-1: embedded plan validation succeeds
  Covers: D-REQ-01

## Implementation Plan

- Step 1: lint the embedded plan
  Verifies: V-AC-1
EOF
    run "$SCRIPT" --task EX-0003 --root "$WORK" --stage plan --format json
    [ "$status" -eq 0 ] && [ -z "$output" ]
}

@test "L3 plan stage requires its dedicated canonical plan" {
    write_clean_fixture
    rm "$WORK/datarim/plans/EX-0001-plan.md"
    run "$SCRIPT" --task EX-0001 --root "$WORK" --stage plan --format json
    [ "$status" -eq 2 ] \
      && [[ "$output" == *"required canonical plan missing for L3 task"* ]] \
      && [[ "$output" == *"datarim/plans/EX-0001-plan.md"* ]]
}

@test "explicit PRD L3 takes precedence over stale L2 task metadata" {
    write_clean_fixture
    sed -i.bak 's/Level 3/Level 2/' \
      "$WORK/datarim/tasks/EX-0001-task-description.md"
    printf '%s\n' 'complexity: L2' \
      > "$WORK/datarim/tasks/EX-0001-task-description.md"
    rm "$WORK/datarim/plans/EX-0001-plan.md"
    run "$SCRIPT" --task EX-0001 --root "$WORK" --stage plan --format json
    [ "$status" -eq 2 ] \
      && [[ "$output" == *"required canonical plan missing for L3 task"* ]]
}

@test "L2 index fallback resolves the embedded canonical plan" {
    cat >"$WORK/datarim/prd/PRD-EX-0004.md" <<'EOF'
# PRD: Index fallback

#### D-REQ-01: fallback remains consistent

- V-AC-1: embedded validation succeeds
  Covers: D-REQ-01
EOF
    cat >"$WORK/datarim/tasks/EX-0004-task-description.md" <<'EOF'
---
task_id: EX-0004
plan: null
---

## Implementation Plan

- Step 1: lint the embedded plan
  Verifies: V-AC-1
EOF
    printf '%s\n' '- EX-0004 · in_progress · P2 · L2 · Index fallback fixture' \
      > "$WORK/datarim/tasks.md"
    run "$SCRIPT" --task EX-0004 --root "$WORK" --stage plan --format json
    [ "$status" -eq 0 ] && [ -z "$output" ]
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

# ===========================================================================
# TUNE-0473 (A): completeness scan must accept a letter-prefixed axis V-AC id
# (V-AC-A1) cited via `Связанный AC из PRD:` in expectations.md on equal footing
# with the numeric form — regression against a false `no linked V-AC` grade-F
# when coverage is real (TUNE-0471: 7 false errors at 11/11 D-REQ covered).
# ===========================================================================

# Clean L3 fixture whose PRD declares LETTER-PREFIXED axis V-AC ids and whose
# expectations.md links wishes to them. Pre-fix this graded F falsely.
write_axis_fixture() {
    cat >"$WORK/datarim/prd/PRD-EX-0002.md" <<'EOF'
# PRD: Axis Example
**Complexity:** Level 3

## Requirements (D-REQ)

#### D-REQ-01: the validator builds a graph

#### D-REQ-02: the validator emits json

## Success Criteria

- V-AC-A1: graph is built
  Covers: D-REQ-01
- V-AC-A2: json is emitted
  Covers: D-REQ-02
EOF
    cat >"$WORK/datarim/plans/EX-0002-plan.md" <<'EOF'
# Plan: Axis Example
- Step 1: build the graph
  Verifies: V-AC-A1
- Step 2: emit json
  Verifies: V-AC-A2
EOF
    cat >"$WORK/datarim/tasks/EX-0002-task-description.md" <<'EOF'
# Implementation Notes

- Evidence: V-AC-A1 — bats dev-tools/tests/dr-spec-lint.bats
- Evidence: V-AC-A2 — bats dev-tools/tests/dr-spec-lint.bats
EOF
    cat >"$WORK/datarim/tasks/EX-0002-expectations.md" <<'EOF'
- **1. Build graph.**
  - wish_id: build-graph
  - Связанный AC из PRD: V-AC-A1
  - #### Текущий статус
    - pending
- **2. Emit json.**
  - wish_id: emit-json
  - Связанный AC из PRD: V-AC-A2
  - #### Текущий статус
    - pending
EOF
}

@test "TUNE-0473-A: axis-id V-AC (V-AC-A1) cited in expectations.md is NOT a false 'no linked V-AC'" {
    write_axis_fixture
    run "$SCRIPT" --task EX-0002 --root "$WORK" --format json
    [ "$status" -eq 0 ]
    [[ "$output" != *"no linked V-AC"* ]]
    [[ "$output" != *"undeclared"* ]]
}

@test "TUNE-0473-A-neg: a genuinely unlinked wish (dash cite) still flags 'no linked V-AC'" {
    write_axis_fixture
    # Break wish 1's link: replace the cite value with the deliberate no-link dash.
    perl -0pi -e 's/Связанный AC из PRD: V-AC-A1/Связанный AC из PRD: —/' "$WORK/datarim/tasks/EX-0002-expectations.md"
    run "$SCRIPT" --task EX-0002 --root "$WORK" --format json
    [ "$status" -ne 0 ]
    [[ "$output" == *"no linked V-AC"* ]]
}
