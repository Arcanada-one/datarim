#!/usr/bin/env bats
#
# Integration test for dev-tools/dr-spec-lint.sh (R1). Builds a tiny fixture
# spec graph with the exact three defect classes the research probe planted —
# a bad D-REQ slug, a V-AC missing its Covers line, and a dangling Covers ref —
# and asserts dr-spec-lint catches EACH class. This is the falsifiable proof the
# native mechanism closes the documented gap (the external tool returned
# "0 violations" on exactly these defects; ours must not).
#
# Source of the probe: documentation/research/TUNE-0432-specscore-research-report.md § 2.3.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../dr-spec-lint.sh"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/datarim/prd" "$WORK/datarim/plans" "$WORK/datarim/tasks"

    # Defect 1: D-REQ-1 (single digit, bad slug — should be D-REQ-01).
    # Defect 2: V-AC-2 has NO Covers line.
    # Defect 3: V-AC-3 covers D-REQ-77 which is not declared (dangling).
    cat >"$WORK/datarim/prd/PRD-PROBE-0001.md" <<'EOF'
# PRD: Probe
**Complexity:** Level 3

## Requirements (D-REQ)

#### D-REQ-1: bad single-digit slug

#### D-REQ-02: a valid requirement

## Success Criteria

- V-AC-1: covered correctly
  Covers: D-REQ-02
- V-AC-2: this one has no Covers line at all
- V-AC-3: this one points at a non-existent requirement
  Covers: D-REQ-77
EOF
    cat >"$WORK/datarim/plans/PROBE-0001-plan.md" <<'EOF'
# Plan: Probe
- V-AC-1 implemented with a test
EOF
    cat >"$WORK/datarim/tasks/PROBE-0001-expectations.md" <<'EOF'
- wish_id: probe-wish
EOF
}

teardown() {
    rm -rf "$WORK"
}

@test "exit is non-zero (defects present, hard mode)" {
    run "$SCRIPT" --task PROBE-0001 --root "$WORK" --format json
    [ "$status" -ne 0 ]
    [ "$status" -ne 2 ]   # must be a real violation count, not a usage error
}

@test "catches the bad D-REQ slug (dreq-id-format)" {
    run "$SCRIPT" --task PROBE-0001 --root "$WORK" --format json
    [[ "$output" == *'"check_name": "dreq-id-format"'* ]]
}

@test "catches the V-AC missing its Covers line (vac-covers-present)" {
    run "$SCRIPT" --task PROBE-0001 --root "$WORK" --format json
    [[ "$output" == *'"check_name": "vac-covers-present"'* ]]
}

@test "catches the dangling Covers reference (dreq-dangling)" {
    run "$SCRIPT" --task PROBE-0001 --root "$WORK" --format json
    [[ "$output" == *'"check_name": "dreq-dangling"'* ]]
}

@test "all three defect classes appear in one run" {
    run "$SCRIPT" --task PROBE-0001 --root "$WORK" --format json
    [[ "$output" == *"dreq-id-format"* ]]
    [[ "$output" == *"vac-covers-present"* ]]
    [[ "$output" == *"dreq-dangling"* ]]
}

@test "every emitted finding is valid JSON" {
    run "$SCRIPT" --task PROBE-0001 --root "$WORK" --format json
    printf '%s\n' "$output" | python3 -c 'import json,sys; [json.loads(l) for l in sys.stdin if l.strip()]'
}
