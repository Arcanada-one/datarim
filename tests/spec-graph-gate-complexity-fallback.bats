#!/usr/bin/env bats
#
# Contract test for dev-tools/spec-graph-gate.sh complexity fallback (TUNE-0444).
#
# When neither a PRD nor a task-description file exists, the gate cannot resolve
# the task complexity from those artefacts and historically defaulted to L3,
# which made the no-PRD branch fail-close with exit 2 ("required PRD missing").
# That is a false-positive for an inline-executed L2 task (PRD legitimately
# waived). The fallback reads the complexity from the backlog / tasks one-liner
# index (the row already carries `· L2 ·`) BEFORE fail-closing, so the gate
# takes its own L1/L2 skip branch.
#
# DoD (from TUNE-0444 backlog row):
#   gate exits 0 (decision:skip) for an L2 task with a backlog row but no
#   PRD/task-description.

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

# ---------- DoD: L2 backlog row, no PRD/task-desc → skip exit 0 ----------

@test "SKIP: L2 task from backlog one-liner, no PRD/task-description" {
    printf -- '- FAKE-0002 · pending · P3 · L2 · A doc-sync task → tasks/FAKE-0002-task-description.md\n' >> "$BACKLOG"
    run "$GATE" --task FAKE-0002 --stage compliance --root "$WORK" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision":"skip"'* ]]
    [[ "$output" == *'"complexity":"L2"'* ]]
}

@test "SKIP: L1 task from backlog one-liner, no PRD/task-description" {
    printf -- '- FAKE-0001 · pending · P3 · L1 · A trivial fix → tasks/FAKE-0001-task-description.md\n' >> "$BACKLOG"
    run "$GATE" --task FAKE-0001 --stage do --root "$WORK" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision":"skip"'* ]]
    [[ "$output" == *'"complexity":"L1"'* ]]
}

@test "SKIP: L2 task resolved from the active tasks.md index when not in backlog" {
    printf -- '- FAKE-0003 · in_progress · P2 · L2 · Active doc-sync → tasks/FAKE-0003-task-description.md\n' >> "$TASKS"
    run "$GATE" --task FAKE-0003 --stage qa --root "$WORK" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"decision":"skip"'* ]]
    [[ "$output" == *'"complexity":"L2"'* ]]
}

# ---------- regression: L3 task with no PRD still fail-closes (unchanged) ----------

@test "FAIL-CLOSE: L3 backlog row, no PRD → exit 2 (PRD required at L3)" {
    printf -- '- FAKE-0033 · pending · P2 · L3 · A real feature → tasks/FAKE-0033-task-description.md\n' >> "$BACKLOG"
    run "$GATE" --task FAKE-0033 --stage compliance --root "$WORK" --format json
    [ "$status" -eq 2 ]
    [[ "$output" == *"required PRD missing"* ]]
}

@test "FAIL-CLOSE: unknown task absent from both indices, no PRD → exit 2 (default L3)" {
    run "$GATE" --task FAKE-9999 --stage compliance --root "$WORK" --format json
    [ "$status" -eq 2 ]
    [[ "$output" == *"required PRD missing"* ]]
}

# ---------- precedence: task-description still wins over backlog ----------

@test "PRECEDENCE: task-description complexity overrides backlog row" {
    printf -- '- FAKE-0044 · pending · P2 · L3 · Says L3 in backlog → tasks/FAKE-0044-task-description.md\n' >> "$BACKLOG"
    printf -- 'complexity: L2\n' > "$WORK/datarim/tasks/FAKE-0044-task-description.md"
    run "$GATE" --task FAKE-0044 --stage compliance --root "$WORK" --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"complexity":"L2"'* ]]
    [[ "$output" == *'"decision":"skip"'* ]]
}
