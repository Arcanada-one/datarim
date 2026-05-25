#!/usr/bin/env bats
# tasks.bats — V-AC верификация `datarim tasks {list,show}`.

setup() {
    DATARIM_CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TASKS_SH="$DATARIM_CLI_DIR/subcommands/tasks.sh"
    [[ -f "$TASKS_SH" ]] || skip "subcommands/tasks.sh not yet implemented"

    FIX="$BATS_TMPDIR/wsr-$$"
    mkdir -p "$FIX/datarim/tasks" "$FIX/datarim/prd" "$FIX/datarim/plans" "$FIX/datarim/reflection"
    cat > "$FIX/datarim/tasks.md" <<'EOF'
# Tasks

## Active

- TUNE-0268 · in_progress · P2 · L3 · CLI tool → tasks/TUNE-0268-init-task.md
- ARCA-0001 · in_progress · P1 · L4 · Assistant Agent → tasks/ARCA-0001-task-description.md
EOF
    cat > "$FIX/datarim/tasks/TUNE-0268-init-task.md" <<'EOF'
# TUNE-0268 init-task

Operator brief verbatim text here.
EOF
    cat > "$FIX/datarim/prd/PRD-TUNE-0268.md" <<'EOF'
# PRD TUNE-0268
PRD body.
EOF
    cat > "$FIX/datarim/plans/TUNE-0268-plan.md" <<'EOF'
# Plan TUNE-0268
Plan body.
EOF
    cat > "$FIX/datarim/reflection/reflection-TUNE-0268.md" <<'EOF'
# Reflection TUNE-0268
Reflection body.
EOF
}

teardown() {
    [[ -n "${FIX:-}" ]] && rm -rf "$FIX"
}

@test "1: tasks list plain mode emits all active IDs" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$TASKS_SH" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"TUNE-0268"* ]]
    [[ "$output" == *"ARCA-0001"* ]]
}

@test "2: tasks list --json emits foundation envelope with data.tasks array" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$TASKS_SH" list --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.command == "tasks list"' >/dev/null
    echo "$output" | jq -e '.data.tasks | length == 2' >/dev/null
    echo "$output" | jq -e '.data.tasks[0].id == "TUNE-0268"' >/dev/null
}

@test "3: tasks show <ID> concatenates init-task + PRD + plan + reflection" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$TASKS_SH" show TUNE-0268
    [ "$status" -eq 0 ]
    [[ "$output" == *"TUNE-0268 init-task"* ]]
    [[ "$output" == *"PRD TUNE-0268"* ]]
    [[ "$output" == *"Plan TUNE-0268"* ]]
    [[ "$output" == *"Reflection TUNE-0268"* ]]
}

@test "4: tasks show <unknown> → exit 31 NOT_FOUND" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$TASKS_SH" show DOES-9999
    [ "$status" -eq 31 ]
}

@test "5: tasks (no subcommand) → exit 2 MISUSE" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$TASKS_SH"
    [ "$status" -eq 2 ]
}

@test "6: tasks show --json emits envelope with data.task_id + sections array" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$TASKS_SH" show TUNE-0268 --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.command == "tasks show"' >/dev/null
    echo "$output" | jq -e '.data.task_id == "TUNE-0268"' >/dev/null
    echo "$output" | jq -e '.data.sections | length >= 1' >/dev/null
}
