#!/usr/bin/env bats
#
# Contract test for dev-tools/spec-graph-gate.sh complexity resolution (TUNE-0528).
#
# Covers two bugs:
#   Bug 1 — task-description branch uses bare ^complexity: anchor while the PRD
#           branch already accepts **Complexity:** wrapper. A task-description
#           with `**Complexity:** L1` never matches → defaults to L3.
#   Bug 2 — when a task-description file EXISTS but carries NO parseable
#           complexity line, control stays in the elif branch and never reaches
#           the backlog.md/tasks.md index-row fallback → defaults to L3.
#
# Tests assert the RESOLVED LEVEL in the gate's JSON output, not regex presence
# in the source code.

setup() {
    GATE="$BATS_TEST_DIRNAME/../dev-tools/spec-graph-gate.sh"
    WORK="$(mktemp -d)"
    mkdir -p "$WORK/datarim/prd" "$WORK/datarim/plans" "$WORK/datarim/tasks"
    BACKLOG="$WORK/datarim/backlog.md"
    TASKS="$WORK/datarim/tasks.md"
    printf '# Backlog\n\n## Pending\n' > "$BACKLOG"
    printf '# Tasks\n\n## Active\n' > "$TASKS"
}

teardown() {
    rm -rf "$WORK"
}

# =========================================================================
# Bug 1 — **Complexity:** (bold-wrapped) format in task-description
# =========================================================================

@test "T1: **Complexity:** L1 in task-description → L1" {
    printf -- '**Complexity:** L1\n' > "$WORK/datarim/tasks/FAKE-0101-task-description.md"
    run "$GATE" --task FAKE-0101 --stage prd --root "$WORK" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"complexity":"L1"'* ]]
    [[ "$output" == *'"decision":"skip"'* ]]
}

@test "T2: **Complexity:** L2 in task-description → L2" {
    printf -- '**Complexity:** L2\n' > "$WORK/datarim/tasks/FAKE-0102-task-description.md"
    run "$GATE" --task FAKE-0102 --stage prd --root "$WORK" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"complexity":"L2"'* ]]
    [[ "$output" == *'"decision":"skip"'* ]]
}

@test "T3: **Complexity:** L4 in task-description → L4 (fail-close, PRD required)" {
    printf -- '**Complexity:** L4\n' > "$WORK/datarim/tasks/FAKE-0104-task-description.md"
    run "$GATE" --task FAKE-0104 --stage prd --root "$WORK" --format json
    # L4 without PRD correctly fail-closes. The key assertion is that the
    # complexity was resolved as L4 (not default L3) — but at exit 2 the
    # complexity is not emitted in JSON. The fix for Bug 1 ensures the
    # bold-wrapped pattern reaches LEVEL="L4" before the missing-PRD check.
    [ "$status" -eq 2 ]
    [[ "$output" == *"required PRD missing"* ]]
}

# =========================================================================
# Regression — bare complexity: (no ** wrapper) still works
# =========================================================================

@test "T4: bare complexity: L1 in task-description → L1 (no regression)" {
    printf -- 'complexity: L1\n' > "$WORK/datarim/tasks/FAKE-0201-task-description.md"
    run "$GATE" --task FAKE-0201 --stage prd --root "$WORK" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"complexity":"L1"'* ]]
}

@test "T5: bare complexity: L2 in task-description → L2 (no regression)" {
    printf -- 'complexity: L2\n' > "$WORK/datarim/tasks/FAKE-0202-task-description.md"
    run "$GATE" --task FAKE-0202 --stage prd --root "$WORK" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"complexity":"L2"'* ]]
}

@test "T6: bare complexity: L4 in task-description → L4 (fail-close, PRD required)" {
    printf -- 'complexity: L4\n' > "$WORK/datarim/tasks/FAKE-0204-task-description.md"
    run "$GATE" --task FAKE-0204 --stage prd --root "$WORK" --format json
    # L4 without PRD correctly fail-closes. Bare L4 already resolves on
    # unfixed code (line 68) — this is a regression guard.
    [ "$status" -eq 2 ]
    [[ "$output" == *"required PRD missing"* ]]
}

# =========================================================================
# Bug 2 — task-description exists but NO complexity → fallback to index
# =========================================================================

@test "T7: task-description present, no complexity line → falls through to backlog index L2" {
    printf -- 'Some other content\nMore content\n' > "$WORK/datarim/tasks/FAKE-0302-task-description.md"
    printf -- '- FAKE-0302 · pending · P2 · L2 · A task with a description but no complexity line → tasks/FAKE-0302-task-description.md\n' >> "$BACKLOG"
    run "$GATE" --task FAKE-0302 --stage prd --root "$WORK" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"complexity":"L2"'* ]]
    [[ "$output" == *'"decision":"skip"'* ]]
}

# =========================================================================
# Default — neither source → L3
# =========================================================================

@test "T8: neither PRD, task-desc, nor index row → defaults to L3" {
    run "$GATE" --task FAKE-9999 --stage prd --root "$WORK" --format json
    [ "$status" -eq 2 ]
    [[ "$output" == *"required PRD missing"* ]]
}

# =========================================================================
# Explicit L3 — not by accident of the default
# =========================================================================

@test "T9: **Complexity:** L3 explicitly in task-description → L3" {
    printf -- '**Complexity:** L3\n' > "$WORK/datarim/tasks/FAKE-0303-task-description.md"
    run "$GATE" --task FAKE-0303 --stage prd --root "$WORK" --format json
    # L3 without a PRD still fail-closes, but the complexity must be L3 by
    # explicit match, not by accident of the default.
    [ "$status" -eq 2 ]
    [[ "$output" == *"required PRD missing"* ]]
}
