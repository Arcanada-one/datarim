#!/usr/bin/env bats
# tasks-move.bats — `datarim tasks move <TASK-ID> <target-phase>` (Phase 2b).
# Source: plan TUNE-0268 § Phase 2 step 2.6 + interface block at line 308-326.

setup() {
    DATARIM_CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SUT="$DATARIM_CLI_DIR/subcommands/tasks.sh"
    [[ -f "$SUT" ]] || skip "subcommands/tasks.sh not yet present"

    FIX="$BATS_TMPDIR/wsr-move-$$"
    mkdir -p "$FIX/datarim/tasks"
    cat > "$FIX/datarim/tasks.md" <<'EOF'
# Active Tasks
- TUNE-3001 · pending · P2 · L2 · Test fixture task A → tasks/TUNE-3001-task-description.md
- TUNE-3002 · in_progress · P3 · L1 · Test fixture task B → tasks/TUNE-3002-task-description.md
EOF
    cat > "$FIX/datarim/tasks/TUNE-3001-init-task.md" <<'EOF'
---
task_id: TUNE-3001
artifact: init-task
---
# Operator brief (verbatim)
Fixture brief for TUNE-3001.

## Append-log
EOF
    cat > "$FIX/datarim/tasks/TUNE-3002-init-task.md" <<'EOF'
---
task_id: TUNE-3002
artifact: init-task
---
# Operator brief (verbatim)
Fixture brief for TUNE-3002.

## Append-log
EOF

    export DATARIM_CLI_HALT_PATH="$FIX/.HALT-absent"
    export DATARIM_CLI_AGENT_ID="bats-move-$$"
    export DATARIM_CLI_AUDIT_DIR="$FIX/datarim/audit"
}

teardown() { [[ -z "${FIX:-}" ]] || rm -rf "$FIX"; }

@test "1: move TUNE-3001 to do → status pending → in_progress, exit 0" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" move TUNE-3001 do
    [ "$status" -eq 0 ]
    grep -q "TUNE-3001 · in_progress · P2 · L2" "$FIX/datarim/tasks.md"
    [ -d "$FIX/datarim/audit" ]
}

@test "2: move already in_progress → no-op, exit 0" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" move TUNE-3002 qa
    [ "$status" -eq 0 ]
    # Status remains in_progress.
    grep -q "TUNE-3002 · in_progress · P3 · L1" "$FIX/datarim/tasks.md"
}

@test "3: invalid target-phase → exit 32 INVALID_COMMAND" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" move TUNE-3001 banana
    [ "$status" -eq 32 ]
    [[ "$output" == *"INVALID_COMMAND"* ]]
    # Status unchanged.
    grep -q "TUNE-3001 · pending · P2 · L2" "$FIX/datarim/tasks.md"
}

@test "4: unknown TASK-ID → exit 31 NOT_FOUND" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" move TUNE-9999 do
    [ "$status" -eq 31 ]
    [[ "$output" == *"NOT_FOUND"* ]]
}

@test "5: invalid TASK-ID format → exit 2 MISUSE (path-traversal defense)" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" move '../etc' do
    [ "$status" -eq 2 ]
}

@test "6: missing target-phase → exit 2 MISUSE" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" move TUNE-3001
    [ "$status" -eq 2 ]
}

@test "7: --json envelope on success" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" move TUNE-3001 do --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.command == "tasks move"' >/dev/null
    echo "$output" | jq -e '.data.task_id == "TUNE-3001"' >/dev/null
    echo "$output" | jq -e '.data.target_phase == "do"' >/dev/null
    echo "$output" | jq -e '.data.status_after == "in_progress"' >/dev/null
}

@test "8: kill-switch engaged → exit 17, no mutation" {
    : > "$FIX/.HALT-engaged"
    DATARIM_CLI_HALT_PATH="$FIX/.HALT-engaged" DATARIM_WORKSPACE_ROOT="$FIX" \
        run "$SUT" move TUNE-3001 do
    [ "$status" -eq 17 ]
    grep -q "TUNE-3001 · pending · P2 · L2" "$FIX/datarim/tasks.md"
}

@test "9: --reason triggers append-init-task-qa.sh (Q&A round-trip)" {
    # Reason routes a Q&A block into init-task append-log; verify it lands.
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" move TUNE-3001 do --reason "operator-advance via CLI"
    [ "$status" -eq 0 ]
    grep -q "Q&A by /dr-do" "$FIX/datarim/tasks/TUNE-3001-init-task.md"
    grep -q "operator-advance via CLI" "$FIX/datarim/tasks/TUNE-3001-init-task.md"
}
