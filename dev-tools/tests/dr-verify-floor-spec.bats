#!/usr/bin/env bats
#
# bats spec for the spec-graph integration in dev-tools/dr-verify-floor.sh (R6).
# The floor shells dr-spec-lint --format json and re-emits its findings with
# source_layer "floor" and check_name "dr-spec-lint:<rule>". No new verdict
# enum; the floor's existing exit contract (= high-severity count) is preserved.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../dr-verify-floor.sh"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/datarim/prd" "$WORK/datarim/plans" "$WORK/datarim/tasks"
    # A graph with a dangling Covers (error severity -> high in the floor).
    cat >"$WORK/datarim/prd/PRD-FL-0001.md" <<'EOF'
# PRD: Floor
**Complexity:** Level 3

## Requirements (D-REQ)

#### D-REQ-01: a requirement

## Success Criteria

- V-AC-1: covers a non-existent requirement
  Covers: D-REQ-99
EOF
    cat >"$WORK/datarim/plans/FL-0001-plan.md" <<'EOF'
# Plan
- Step 1: implement floor integration
  Verifies: V-AC-1
EOF
    cat >"$WORK/datarim/tasks/FL-0001-expectations.md" <<'EOF'
- wish_id: floor-wish
EOF
}

teardown() {
    rm -rf "$WORK"
}

@test "floor re-emits spec-lint findings with source_layer floor" {
    run "$SCRIPT" --task FL-0001 --stage plan --workspace "$WORK"
    [[ "$output" == *'"source_layer": "floor"'* ]]
    [[ "$output" == *'dr-spec-lint:'* ]]
}

@test "spec finding carries a dr-spec-lint: prefixed check_name" {
    run "$SCRIPT" --task FL-0001 --stage plan --workspace "$WORK"
    [[ "$output" == *'"check_name": "dr-spec-lint:dreq-dangling"'* ]] || [[ "$output" == *'dr-spec-lint:covers-resolves'* ]]
}

@test "floor exit equals high-severity count (contract preserved)" {
    run "$SCRIPT" --task FL-0001 --stage plan --workspace "$WORK"
    # The floor's contract is exit = count of high-severity findings (NOT a
    # usage code). The dangling Covers yields two high findings
    # (dreq-dangling + covers-resolves), so exit must equal that count.
    high="$(printf '%s\n' "$output" | grep -c '"severity": "high"')"
    [ "$status" -eq "$high" ]
    [ "$status" -ge 1 ]
}

@test "every emitted finding is valid JSON" {
    run "$SCRIPT" --task FL-0001 --stage plan --workspace "$WORK"
    # filter to JSON lines (the floor also prints [..] progress to stderr only)
    printf '%s\n' "$output" | grep '^{' | python3 -c 'import json,sys; [json.loads(l) for l in sys.stdin if l.strip()]'
}

@test "clean graph adds no spec findings" {
    cat >"$WORK/datarim/prd/PRD-CLN-0001.md" <<'EOF'
# PRD: Clean
**Complexity:** Level 3

## Requirements (D-REQ)

#### D-REQ-01: a requirement

## Success Criteria

- V-AC-1: covers it
  Covers: D-REQ-01
EOF
    cat >"$WORK/datarim/plans/CLN-0001-plan.md" <<'EOF'
- Step 1: implement clean graph
  Verifies: V-AC-1
EOF
    cat >"$WORK/datarim/tasks/CLN-0001-expectations.md" <<'EOF'
- **1. Clean graph.**
  - wish_id: clean-graph
  - Связанный AC из PRD: V-AC-1
  - #### Текущий статус
    - pending
EOF
    run "$SCRIPT" --task CLN-0001 --stage plan --workspace "$WORK"
    [[ "$output" != *'dr-spec-lint:'* ]]
}

@test "adapter configuration failure is not converted to a clean floor" {
    cat >"$WORK/datarim/prd/PRD-CFG-0001.md" <<'EOF'
# PRD: Config
**Complexity:** Level 2
EOF
    cat >"$WORK/datarim/plans/CFG-0001-plan.md" <<'EOF'
# Plan
EOF
    run env DATARIM_SPEC_GRAPH_MODE=invalid "$SCRIPT" \
        --task CFG-0001 --stage plan --workspace "$WORK"
    [ "$status" -ge 1 ] \
      && printf '%s\n' "$output" | grep -qF 'spec-graph-gate:configuration'
}

@test "retrospective all-stage verification does not require legacy expectations" {
    cat >"$WORK/datarim/prd/PRD-LEG-0001.md" <<'EOF'
# PRD: Legacy
**Complexity:** Level 3

## Requirements (D-REQ)

#### D-REQ-01: legacy requirement

## Success Criteria

- V-AC-1: covers it
  Covers: D-REQ-01
EOF
    cat >"$WORK/datarim/plans/LEG-0001-plan.md" <<'EOF'
- Step 1: legacy implementation
  Verifies: V-AC-1
EOF
    run "$SCRIPT" --task LEG-0001 --stage all --workspace "$WORK"
    [ "$status" -eq 0 ] \
      && [[ "$output" != *'spec-graph-gate:configuration'* ]]
}
