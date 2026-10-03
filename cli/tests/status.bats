#!/usr/bin/env bats
# status.bats — V-AC-1 верификация native file reader status.
# Source: creative-TUNE-0268-architecture-status-format.md (Option C).

setup() {
    DATARIM_CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    STATUS_SH="$DATARIM_CLI_DIR/subcommands/status.sh"
    [[ -f "$STATUS_SH" ]] || skip "subcommands/status.sh not yet implemented"

    # Build minimal fixture workspace.
    FIX="$BATS_TMPDIR/wsr-$$"
    mkdir -p "$FIX/datarim" "$FIX/documentation/archive/framework"
    cat > "$FIX/datarim/activeContext.md" <<'EOF'
# Active Context

## Active Tasks

- TUNE-0268 · in_progress · P2 · L3 · CLI tool → tasks/TUNE-0268-init-task.md
- ARCA-0001 · in_progress · P1 · L4 · Assistant Agent → tasks/ARCA-0001-task-description.md
- DISK-0036 · blocked · P2 · L2 · Hermes sync → tasks/DISK-0036-task-description.md
EOF
    cat > "$FIX/datarim/backlog.md" <<'EOF'
# Backlog

## Pending

- TUNE-1001 · pending · P3 · L1 · Idea A → tasks/TUNE-1001-task-description.md
- TUNE-1002 · pending · P3 · L1 · Idea B → tasks/TUNE-1002-task-description.md
- DISK-1003 · deferred · P4 · L2 · Maybe later → tasks/DISK-1003-task-description.md
EOF
    cat > "$FIX/documentation/archive/framework/archive-TUNE-9001.md" <<'EOF'
---
id: TUNE-9001
title: "Done thing one"
status: archived
completed_date: 2026-05-20
---
EOF
    cat > "$FIX/documentation/archive/framework/archive-TUNE-9002.md" <<'EOF'
---
id: TUNE-9002
title: "Done thing two"
status: archived
completed_date: 2026-05-22
---
EOF
}

teardown() {
    [[ -n "${FIX:-}" ]] && rm -rf "$FIX"
}

@test "1: plain mode prints 4 sections in canonical order" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$STATUS_SH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"=== Active Tasks ==="* ]]
    [[ "$output" == *"=== Backlog ==="* ]]
    [[ "$output" == *"=== Recently completed ==="* ]]
    [[ "$output" == *"=== Next step ==="* ]]

    # Order check: Active Tasks before Backlog before Recently completed before Next step.
    active_pos=$(echo "$output" | grep -n "Active Tasks" | head -1 | cut -d: -f1)
    backlog_pos=$(echo "$output" | grep -n "Backlog" | head -1 | cut -d: -f1)
    recent_pos=$(echo "$output" | grep -n "Recently completed" | head -1 | cut -d: -f1)
    next_pos=$(echo "$output" | grep -n "Next step" | head -1 | cut -d: -f1)
    [ "$active_pos" -lt "$backlog_pos" ]
    [ "$backlog_pos" -lt "$recent_pos" ]
    [ "$recent_pos" -lt "$next_pos" ]
}

@test "2: plain mode lists all 3 active task IDs" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$STATUS_SH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TUNE-0268"* ]]
    [[ "$output" == *"ARCA-0001"* ]]
    [[ "$output" == *"DISK-0036"* ]]
}

@test "3: plain mode shows backlog count" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$STATUS_SH"
    [ "$status" -eq 0 ]
    # backlog: 3 total — pending=2, deferred=1
    [[ "$output" == *"3"* ]]
}

@test "4: --json mode emits foundation envelope with 4 data sections" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$STATUS_SH" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.version == "1"' >/dev/null
    echo "$output" | jq -e '.command == "status"' >/dev/null
    echo "$output" | jq -e '.data.active | length == 3' >/dev/null
    echo "$output" | jq -e '.data.active[0].id == "TUNE-0268"' >/dev/null
    echo "$output" | jq -e '.data.backlog.count == 3' >/dev/null
    echo "$output" | jq -e '.data.recent | length == 2' >/dev/null
    echo "$output" | jq -e '.data.next.command | test("/dr-")' >/dev/null
    echo "$output" | jq -e '.error == null' >/dev/null
}

@test "5: missing activeContext.md → exit 31 NOT_FOUND" {
    EMPTY="$BATS_TMPDIR/empty-$$"
    mkdir -p "$EMPTY/datarim"
    DATARIM_WORKSPACE_ROOT="$EMPTY" run "$STATUS_SH"
    [ "$status" -eq 31 ]
    rm -rf "$EMPTY"
}

@test "6: backlog.md missing → backlog section still rendered with count=0" {
    NOBACK="$BATS_TMPDIR/noback-$$"
    mkdir -p "$NOBACK/datarim" "$NOBACK/documentation/archive/framework"
    cp "$FIX/datarim/activeContext.md" "$NOBACK/datarim/"
    DATARIM_WORKSPACE_ROOT="$NOBACK" run "$STATUS_SH" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.data.backlog.count == 0' >/dev/null
    rm -rf "$NOBACK"
}
