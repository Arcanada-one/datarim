#!/usr/bin/env bats
#
# bats spec for dev-tools/dr-lint.sh (R4) — umbrella façade over the named-rule
# registry. Covers: rules introspection, --rules subset, --ignore mandatory =
# exit 2, unknown rule = exit 2, empty effective set = exit 2, clean run = 0.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../dr-lint.sh"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/datarim/prd" "$WORK/datarim/plans" "$WORK/datarim/tasks"
    cat >"$WORK/datarim/prd/PRD-LN-0001.md" <<'EOF'
# PRD: Lint
**Complexity:** Level 3

## Requirements (D-REQ)

#### D-REQ-01: a requirement

## Success Criteria

- V-AC-1: covers it
  Covers: D-REQ-01
EOF
    cat >"$WORK/datarim/plans/LN-0001-plan.md" <<'EOF'
- Step 1: implement lint
  Verifies: V-AC-1
EOF
    cat >"$WORK/datarim/tasks/LN-0001-task-description.md" <<'EOF'
## Implementation Notes
- Evidence: V-AC-1 — bats dev-tools/tests/dr-lint.bats
EOF
    cat >"$WORK/datarim/tasks/LN-0001-expectations.md" <<'EOF'
- **1. Lint wish.**
  - wish_id: lint-wish
  - Связанный AC из PRD: V-AC-1
  - #### Текущий статус
    - pending
EOF
}

teardown() {
    rm -rf "$WORK"
}

@test "rules subcommand lists the registry" {
    run "$SCRIPT" rules
    [ "$status" -eq 0 ]
    [[ "$output" == *"dreq-id-format"* ]]
    [[ "$output" == *"graph-complete-l3"* ]]
}

@test "rules --format json emits valid JSON" {
    run "$SCRIPT" rules --format json
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c '
import json,sys
o=json.loads(sys.stdin.read())
ids=[r["id"] for r in o["rules"]]
assert "dreq-id-format" in ids, ids
assert any(r["mandatory"] for r in o["rules"]), o
'
}

@test "clean fixture full run — exit 0" {
    run "$SCRIPT" --task LN-0001 --root "$WORK"
    [ "$status" -eq 0 ]
}

@test "--rules subset runs only the named rules" {
    run "$SCRIPT" --task LN-0001 --root "$WORK" --rules dreq-id-format
    [ "$status" -eq 0 ]
}

@test "--ignore a mandatory rule — exit 2" {
    run "$SCRIPT" --task LN-0001 --root "$WORK" --ignore graph-complete-l3
    [ "$status" -eq 2 ]
    [[ "$output" == *"mandatory"* ]]
}

@test "--rules with an unknown rule id — exit 2" {
    run "$SCRIPT" --task LN-0001 --root "$WORK" --rules nonexistent-rule
    [ "$status" -eq 2 ]
}

@test "--ignore with an unknown rule id — exit 2" {
    run "$SCRIPT" --task LN-0001 --root "$WORK" --ignore nonexistent-rule
    [ "$status" -eq 2 ]
}

@test "empty effective set (ignore everything non-mandatory leaves only mandatory; ignore a non-existent path) does not falsely pass" {
    # Selecting one optional rule then ignoring it yields an empty effective set.
    run "$SCRIPT" --task LN-0001 --root "$WORK" --rules dreq-orphan --ignore dreq-orphan
    [ "$status" -eq 2 ]
}

@test "unknown subcommand / flag — exit 2" {
    run "$SCRIPT" --task LN-0001 --root "$WORK" --bogus
    [ "$status" -eq 2 ]
}
