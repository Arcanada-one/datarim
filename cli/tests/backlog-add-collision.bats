#!/usr/bin/env bats
# backlog-add-collision.bats — V-AC-3 verification (Phase 2).
# Source: creative-TUNE-0268-architecture-id-collision-probe.md § IP-6
#         + plan TUNE-0268 § Phase 2 step 2.5.

setup() {
    DATARIM_CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SUT="$DATARIM_CLI_DIR/subcommands/backlog.sh"
    [[ -f "$SUT" ]] || skip "subcommands/backlog.sh not yet implemented"
    PROBE="$DATARIM_CLI_DIR/lib/id-collision-probe.sh"
    [[ -f "$PROBE" ]] || skip "lib/id-collision-probe.sh not yet implemented"

    FIX="$BATS_TMPDIR/wsr-add-$$"
    mkdir -p "$FIX/datarim/tasks" "$FIX/datarim/prd" "$FIX/documentation/archive/framework"
    cat > "$FIX/datarim/backlog.md" <<'EOF'
# Backlog
- TUNE-2001 · pending · P3 · L1 · Idea A → tasks/TUNE-2001-task-description.md
- ARCA-2002 · pending · P3 · L2 · Idea B → tasks/ARCA-2002-task-description.md
EOF
    # Suppress kill-switch by overriding to a known-absent path.
    export DATARIM_CLI_HALT_PATH="$FIX/.HALT-absent"
    export DATARIM_CLI_AGENT_ID="bats-agent-$$"
    # Isolate audit dir.
    export DATARIM_CLI_AUDIT_DIR="$FIX/datarim/audit"
}

teardown() { [[ -z "${FIX:-}" ]] || rm -rf "$FIX"; }

@test "1: no-collision add → exit 0, appended line, audit recorded" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" add \
        --id TUNE-9001 --priority P3 --complexity L2 --title 'Fresh new idea'
    [ "$status" -eq 0 ]
    grep -q "TUNE-9001 · pending · P3 · L2 · Fresh new idea" "$FIX/datarim/backlog.md"
    [ -d "$FIX/datarim/audit" ]
    ls "$FIX/datarim/audit"/cli-audit-*.jsonl >/dev/null
}

@test "2: collision in workspace backlog → exit 28 ID_COLLISION_DETECTED" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" add \
        --id TUNE-2001 --priority P3 --complexity L1 --title 'Duplicate'
    [ "$status" -eq 28 ]
    [[ "$output" == *"ID_COLLISION_DETECTED"* ]]
    # Backlog must not gain a duplicate line.
    occurrences=$(grep -c '^- TUNE-2001 ·' "$FIX/datarim/backlog.md")
    [ "$occurrences" -eq 1 ]
}

@test "3: collision in archive file → exit 28, source_type=archive in JSON envelope" {
    cat > "$FIX/documentation/archive/framework/archive-TUNE-9999.md" <<'EOF'
---
task_id: TUNE-9999
---
# TUNE-9999 archived task
EOF
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" add --json \
        --id TUNE-9999 --priority P3 --complexity L1 --title 'Conflict with archive'
    [ "$status" -eq 28 ]
    echo "$output" | jq -e '.error.code == "ID_COLLISION_DETECTED"' >/dev/null
    echo "$output" | jq -e '.error.exit == 28' >/dev/null
    echo "$output" | jq -e '.data.collisions | length >= 1' >/dev/null
    echo "$output" | jq -e '[.data.collisions[].source_type] | any(. == "archive")' >/dev/null
}

@test "4: multi-instance 3-way collision → all sources reported" {
    cat > "$FIX/documentation/archive/framework/archive-TUNE-8000.md" <<'EOF'
---
task_id: TUNE-8000
---
EOF
    cat > "$FIX/datarim/tasks/TUNE-8000-task-description.md" <<'EOF'
---
task_id: TUNE-8000
---
EOF
    # Also seed backlog.
    printf -- '- TUNE-8000 · pending · P3 · L1 · Pre-existing → tasks/TUNE-8000-task-description.md\n' \
        >> "$FIX/datarim/backlog.md"
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" add --json \
        --id TUNE-8000 --priority P3 --complexity L1 --title 'Triple conflict'
    [ "$status" -eq 28 ]
    n=$(echo "$output" | jq '.data.collisions | length')
    [ "$n" -ge 3 ]
    # Each source_type observed at least once.
    echo "$output" | jq -e '[.data.collisions[].source_type] | any(. == "archive")' >/dev/null
    echo "$output" | jq -e '[.data.collisions[].source_type] | any(. == "backlog")' >/dev/null
    echo "$output" | jq -e '[.data.collisions[].source_type] | any(. == "tasks_md")' >/dev/null
}

@test "5: sync-conflict file is skipped (no false-positive collision)" {
    cat > "$FIX/datarim/backlog.sync-conflict-20260524-XYZ.md" <<'EOF'
# Backlog
- TUNE-7777 · pending · P3 · L1 · Stale sync-conflict entry → tasks/TUNE-7777-task-description.md
EOF
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" add \
        --id TUNE-7777 --priority P3 --complexity L1 --title 'Should not collide'
    [ "$status" -eq 0 ]
    grep -q "TUNE-7777 · pending · P3 · L1 · Should not collide" "$FIX/datarim/backlog.md"
}

@test "6: invalid ID format → exit 2 MISUSE (path-traversal defense)" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" add \
        --id '../../etc/passwd' --priority P3 --complexity L1 --title 'Pwn'
    [ "$status" -eq 2 ]
}

@test "7: missing required flag → exit 2 MISUSE" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" add --id TUNE-9100 --title 'Missing prio'
    [ "$status" -eq 2 ]
}

@test "8: framework's own Projects/Datarim path excluded from probe" {
    mkdir -p "$FIX/Projects/Datarim/datarim"
    cat > "$FIX/Projects/Datarim/datarim/backlog.md" <<'EOF'
- TUNE-6500 · pending · P3 · L1 · Framework-local entry → tasks/TUNE-6500-task-description.md
EOF
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" add \
        --id TUNE-6500 --priority P3 --complexity L1 --title 'Consumer overrides framework'
    [ "$status" -eq 0 ]
    grep -q "TUNE-6500 · pending · P3 · L1 · Consumer overrides framework" "$FIX/datarim/backlog.md"
}

@test "9: kill-switch engaged → exit 17 before any work" {
    : > "$FIX/.HALT-engaged"
    DATARIM_CLI_HALT_PATH="$FIX/.HALT-engaged" DATARIM_WORKSPACE_ROOT="$FIX" \
        run "$SUT" add --id TUNE-9200 --priority P3 --complexity L1 --title 'Halted'
    [ "$status" -eq 17 ]
    ! grep -q "TUNE-9200" "$FIX/datarim/backlog.md"
}
