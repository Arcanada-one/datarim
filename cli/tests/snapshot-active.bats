#!/usr/bin/env bats
# snapshot.sh + active.sh smoke tests.

setup() {
    DATARIM_CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SNAP_SH="$DATARIM_CLI_DIR/subcommands/snapshot.sh"
    ACTIVE_SH="$DATARIM_CLI_DIR/subcommands/active.sh"
    [[ -f "$SNAP_SH" && -f "$ACTIVE_SH" ]] || skip "subcommands not yet implemented"

    FIX="$BATS_TMPDIR/wsr-$$"
    mkdir -p "$FIX/datarim/snapshots"
    cat > "$FIX/datarim/snapshots/TUNE-0268.snapshot.md" <<'EOF'
---
task: TUNE-0268
stage: plan
---
## Snapshot body
Some content here.
EOF
    cat > "$FIX/datarim/activeContext.md" <<'EOF'
# Active Context

## Active Tasks

- TUNE-0268 · in_progress · P2 · L3 · CLI tool → tasks/TUNE-0268-init-task.md
- ARCA-0001 · in_progress · P1 · L4 · Assistant → tasks/ARCA-0001-task-description.md

## Other Section
ignored
EOF
}
teardown() { [[ -n "${FIX:-}" ]] && rm -rf "$FIX"; }

@test "1: snapshot show emits file body" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SNAP_SH" show TUNE-0268
    [ "$status" -eq 0 ]
    [[ "$output" == *"Snapshot body"* ]]
    [[ "$output" == *"stage: plan"* ]]
}
@test "2: snapshot show --json envelope" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SNAP_SH" show TUNE-0268 --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.command == "snapshot show"' >/dev/null
    echo "$output" | jq -e '.data.task_id == "TUNE-0268"' >/dev/null
    echo "$output" | jq -e '.data.body | test("Snapshot body")' >/dev/null
}
@test "3: snapshot show unknown ID → exit 31" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SNAP_SH" show DOES-9999
    [ "$status" -eq 31 ]
}
@test "4: active emits all 2 IDs but not Other Section content" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$ACTIVE_SH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TUNE-0268"* ]]
    [[ "$output" == *"ARCA-0001"* ]]
    [[ "$output" != *"ignored"* ]]
}
@test "5: active --json envelope with 2 items" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$ACTIVE_SH" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.data.count == 2' >/dev/null
    echo "$output" | jq -e '.data.active[0].id == "TUNE-0268"' >/dev/null
}
