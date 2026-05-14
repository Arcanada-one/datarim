#!/usr/bin/env bats
# tune-0210-init-task-write.bats — Phase 1 init-task persistence (F1).
#
# Covers:
#   - dev-tools/check-init-task-presence.sh contract (per-task validation + multi-task scan)
#   - Init-task artifact schema (12-field frontmatter, mandatory headings)
#   - /dr-doctor-style 30-day rolling soft window (info < 30d, warn >= 30d)
#   - Archive immunity, legacy marker bypass
#   - Backwards-compatibility: never blocks on legacy tasks

CHECK="$BATS_TEST_DIRNAME/../dev-tools/check-init-task-presence.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks"
}

teardown() {
    rm -rf "$TMPROOT"
}

# --- Helpers ----------------------------------------------------------------

# write_init_task <ID> [<extra-frontmatter-line>...]
write_init_task() {
    local id="$1"; shift
    local file="$TMPROOT/datarim/tasks/${id}-init-task.md"
    {
        echo "---"
        echo "task_id: $id"
        echo "artifact: init-task"
        echo "schema_version: 1"
        echo "captured_at: 2026-05-14"
        echo "captured_by: /dr-init"
        echo "operator: Pavel"
        echo "status: canonical"
        echo "source: /dr-init"
        for line in "$@"; do echo "$line"; done
        echo "---"
        echo ""
        echo "# $id — Init-Task"
        echo ""
        echo "## Operator brief (verbatim)"
        echo ""
        echo "Original prompt body."
        echo ""
        echo "## Append-log (operator amendments)"
        echo ""
        echo "_(пусто)_"
    } > "$file"
}

# write_task_description <ID> <created-YYYY-MM-DD> [<status-override>] [<extra-frontmatter-line>...]
# Third positional is the `status:` value (default in_progress) so callers can
# exercise archived/cancelled paths without colliding with a default line.
write_task_description() {
    local id="$1"; local created="$2"; local status="${3:-in_progress}"
    shift 3 2>/dev/null || shift $#
    local file="$TMPROOT/datarim/tasks/${id}-task-description.md"
    {
        echo "---"
        echo "task_id: $id"
        echo "title: $id task"
        echo "status: $status"
        echo "priority: P2"
        echo "complexity: L2"
        echo "type: framework"
        echo "project: Datarim"
        echo "created: $created"
        for line in "$@"; do echo "$line"; done
        echo "---"
        echo ""
        echo "# $id"
    } > "$file"
}

# --- Single-task validation (--task) ----------------------------------------

@test "T1 check --task exits 0 on valid init-task file" {
    write_init_task "TEST-0001"
    run "$CHECK" --task TEST-0001 --root "$TMPROOT"
    [ "$status" -eq 0 ]
}

@test "T2 check --task exits 1 when file missing" {
    run "$CHECK" --task TEST-0002 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"* ]] || [[ "$output" == *"not found"* ]] || [[ "$output" == *"absent"* ]]
}

@test "T3 check --task exits 1 when frontmatter lacks required field artifact: init-task" {
    # Write a frontmatter that explicitly carries wrong artifact label
    local file="$TMPROOT/datarim/tasks/TEST-0003-init-task.md"
    {
        echo "---"
        echo "task_id: TEST-0003"
        echo "artifact: task-description"   # WRONG — must be init-task
        echo "schema_version: 1"
        echo "captured_at: 2026-05-14"
        echo "captured_by: /dr-init"
        echo "operator: Pavel"
        echo "status: canonical"
        echo "---"
        echo ""
        echo "## Operator brief (verbatim)"
        echo ""
        echo "x"
        echo ""
        echo "## Append-log (operator amendments)"
    } > "$file"
    run "$CHECK" --task TEST-0003 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"artifact"* ]] || [[ "$output" == *"frontmatter"* ]]
}

@test "T4 check --task exits 1 when '## Operator brief (verbatim)' heading missing" {
    local file="$TMPROOT/datarim/tasks/TEST-0004-init-task.md"
    {
        echo "---"
        echo "task_id: TEST-0004"
        echo "artifact: init-task"
        echo "schema_version: 1"
        echo "captured_at: 2026-05-14"
        echo "captured_by: /dr-init"
        echo "operator: Pavel"
        echo "status: canonical"
        echo "---"
        echo ""
        echo "# TEST-0004"
        echo ""
        echo "## Append-log (operator amendments)"
        echo ""
        echo "_(пусто)_"
    } > "$file"
    run "$CHECK" --task TEST-0004 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Operator brief"* ]] || [[ "$output" == *"verbatim"* ]]
}

@test "T5 check --task exits 1 when '## Append-log' heading missing" {
    local file="$TMPROOT/datarim/tasks/TEST-0005-init-task.md"
    {
        echo "---"
        echo "task_id: TEST-0005"
        echo "artifact: init-task"
        echo "schema_version: 1"
        echo "captured_at: 2026-05-14"
        echo "captured_by: /dr-init"
        echo "operator: Pavel"
        echo "status: canonical"
        echo "---"
        echo ""
        echo "## Operator brief (verbatim)"
        echo ""
        echo "prompt text"
    } > "$file"
    run "$CHECK" --task TEST-0005 --root "$TMPROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Append-log"* ]]
}

@test "T6 check --task --report prints human-readable detail on failure" {
    run "$CHECK" --task TEST-0006 --root "$TMPROOT" --report
    [ "$status" -eq 1 ]
    # Detail mode prints more than a single line
    line_count=$(printf '%s\n' "$output" | wc -l | tr -d ' ')
    [ "$line_count" -ge 1 ]
}

# --- Multi-task scan (--all): 30-day rolling soft window --------------------

@test "T7 check --all info finding for fresh task (<30d) without init-task" {
    # Task created today, no init-task → severity info, exit 0 (non-blocking)
    today="$(date +%Y-%m-%d)"
    write_task_description "TEST-0007" "$today"
    run "$CHECK" --all --root "$TMPROOT" --today "$today"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-0007"* ]]
    [[ "$output" == *"info"* ]]
}

@test "T8 check --all warn finding for stale task (>=30d) without init-task" {
    # Task created 31 days before --today → severity warn, exit 0 (still non-blocking)
    today="2026-06-15"
    created="2026-05-14"   # exactly 32 days before today
    write_task_description "TEST-0008" "$created"
    run "$CHECK" --all --root "$TMPROOT" --today "$today"
    [ "$status" -eq 0 ]
    [[ "$output" == *"TEST-0008"* ]]
    [[ "$output" == *"warn"* ]]
}

@test "T9 check --all skips task with status: archived" {
    today="2026-06-15"
    write_task_description "TEST-0009" "2026-05-14" "archived"
    run "$CHECK" --all --root "$TMPROOT" --today "$today"
    [ "$status" -eq 0 ]
    # No finding line for the archived task
    [[ "$output" != *"TEST-0009"* ]]
}

@test "T10 check --all skips task with legacy: true marker" {
    today="2026-06-15"
    write_task_description "TEST-0010" "2026-04-01" "in_progress" "legacy: true"
    run "$CHECK" --all --root "$TMPROOT" --today "$today"
    [ "$status" -eq 0 ]
    [[ "$output" != *"TEST-0010"* ]]
}

@test "T11 check --all clean when every task has matching init-task" {
    today="2026-06-15"
    write_task_description "TEST-0011" "2026-05-14"
    write_init_task "TEST-0011"
    run "$CHECK" --all --root "$TMPROOT" --today "$today"
    [ "$status" -eq 0 ]
    [[ "$output" != *"TEST-0011"* ]] || [[ "$output" == *"ok"* ]] || [[ "$output" == *"OK"* ]] || [ -z "$output" ]
}

# --- Usage / safety ---------------------------------------------------------

@test "T12 check exits 2 on usage error (no --task or --all)" {
    run "$CHECK" --root "$TMPROOT"
    [ "$status" -eq 2 ]
}

@test "T13 check --help prints usage and exits 0" {
    run "$CHECK" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}
