#!/usr/bin/env bats
#
# bats spec for dev-tools/dr-trace.sh (R5) — coverage report. Asserts the five
# buckets (covered / uncovered / dangling / orphaned / explicitly_deferred) in
# both JSON and table form, and that --strict flips the exit to 1.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../dr-trace.sh"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/datarim/prd" "$WORK/datarim/plans" "$WORK/datarim/tasks"
    cat >"$WORK/datarim/prd/PRD-TR-0001.md" <<'EOF'
# PRD: Trace
**Complexity:** Level 3

## Requirements (D-REQ)

#### D-REQ-01: covered requirement

#### D-REQ-02: orphaned requirement (no V-AC)

#### D-REQ-03: explicitly deferred requirement (deferred)

## Success Criteria

- V-AC-1: covers an existing requirement
  Covers: D-REQ-01
- V-AC-2: covers a non-existent requirement (dangling)
  Covers: D-REQ-88
EOF
    cat >"$WORK/datarim/plans/TR-0001-plan.md" <<'EOF'
# Plan
- V-AC-1 implemented with a test
EOF
}

teardown() {
    rm -rf "$WORK"
}

@test "default text table — exit 0" {
    run "$SCRIPT" --task TR-0001 --root "$WORK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"covered"* ]]
    [[ "$output" == *"uncovered"* ]]
    [[ "$output" == *"dangling"* ]]
}

@test "json — five bucket arrays present" {
    run "$SCRIPT" --task TR-0001 --root "$WORK" --format json
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c '
import json,sys
o=json.loads(sys.stdin.read())
for k in ("covered","uncovered","dangling","orphaned","explicitly_deferred"):
    assert k in o, (k, o)
assert "D-REQ-01" in o["covered"], o
assert "D-REQ-02" in o["orphaned"], o
assert "D-REQ-03" in o["explicitly_deferred"], o
assert "D-REQ-88" in o["dangling"], o
'
}

@test "--strict flips exit to 1 when dangling/uncovered present" {
    run "$SCRIPT" --task TR-0001 --root "$WORK" --strict
    [ "$status" -eq 1 ]
}

@test "--strict on a fully clean graph exits 0" {
    cat >"$WORK/datarim/prd/PRD-CLEAN-0001.md" <<'EOF'
# PRD: Clean
**Complexity:** Level 3

## Requirements (D-REQ)

#### D-REQ-01: covered requirement

## Success Criteria

- V-AC-1: covers it
  Covers: D-REQ-01
EOF
    cat >"$WORK/datarim/plans/CLEAN-0001-plan.md" <<'EOF'
- V-AC-1 implemented with a test
EOF
    run "$SCRIPT" --task CLEAN-0001 --root "$WORK" --strict
    [ "$status" -eq 0 ]
}

@test "unknown flag — exit 2" {
    run "$SCRIPT" --task TR-0001 --root "$WORK" --bogus
    [ "$status" -eq 2 ]
}

@test "missing artefacts — exit 2" {
    run "$SCRIPT" --task NOPE-9999 --root "$WORK"
    [ "$status" -eq 2 ]
}
