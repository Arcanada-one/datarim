#!/usr/bin/env bats
# prune-backlog-terminal.bats — unit matrix for dev-tools/prune-backlog-terminal.sh
#
# Contract under test:
#   --check  (dry-run, exit 0, stdout: prunable/surfaced/kept counts)
#   --fix    (rewrite backlog.md; atomic temp-file + mv)
#
# Data-loss-safe contract:
#   (a) terminal entry WITH  archive doc → removed by --fix
#   (b) terminal entry WITHOUT archive doc → PRESERVED + "surfaced:" emitted
#   (c) pending / blocked-pending entries → never touched

SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/prune-backlog-terminal.sh"

# Build a minimal KB root with datarim/backlog.md + documentation/archive/
setup() {
    KB="$(mktemp -d)"
    mkdir -p "$KB/datarim"
    mkdir -p "$KB/documentation/archive/framework"
    mkdir -p "$KB/documentation/archive/cancelled"
}

teardown() { rm -rf "$KB"; }

# Helper: write backlog.md with the given content
write_backlog() {
    printf '%s\n' "$@" > "$KB/datarim/backlog.md"
}

# Helper: create a stub archive doc for an ID
make_archive() {  # $1=area $2=ID
    local area="$1" id="$2"
    mkdir -p "$KB/documentation/archive/$area"
    printf '# Archive — %s\n' "$id" > "$KB/documentation/archive/$area/archive-$id.md"
}

# ---------- (a) terminal + archive doc → removed by --fix ----------

@test "(a) terminal entry with archive doc removed by --fix" {
    write_backlog \
        "# Backlog" \
        "" \
        "## Pending" \
        "" \
        "- TUNE-0001 · done · P2 · L1 · Completed thing → tasks/TUNE-0001-task-description.md" \
        "- INFRA-0099 · pending · P2 · L2 · Survivor → tasks/INFRA-0099-task-description.md"
    make_archive "framework" "TUNE-0001"

    run "$SCRIPT" --root "$KB" --fix
    [ "$status" -eq 0 ]
    # archived entry removed
    run grep -q "TUNE-0001" "$KB/datarim/backlog.md"
    [ "$status" -ne 0 ]
    # survivor kept
    run grep -q "INFRA-0099" "$KB/datarim/backlog.md"
    [ "$status" -eq 0 ]
}

@test "(a) --check dry-run reports prunable without modifying backlog" {
    write_backlog \
        "# Backlog" \
        "" \
        "- TUNE-0002 · archived · P2 · L1 · Another done → tasks/TUNE-0002-task-description.md"
    make_archive "framework" "TUNE-0002"

    run "$SCRIPT" --root "$KB" --check
    [ "$status" -eq 0 ]
    [[ "$output" == *"prunable"* ]]
    # file must be untouched
    run grep -q "TUNE-0002" "$KB/datarim/backlog.md"
    [ "$status" -eq 0 ]
}

@test "(a) completed status also treated as terminal" {
    write_backlog \
        "# Backlog" \
        "" \
        "- TUNE-0003 · completed · P1 · L2 · Done task → tasks/TUNE-0003-task-description.md"
    make_archive "framework" "TUNE-0003"

    run "$SCRIPT" --root "$KB" --fix
    [ "$status" -eq 0 ]
    run grep -q "TUNE-0003" "$KB/datarim/backlog.md"
    [ "$status" -ne 0 ]
}

@test "(a) terminal-cancelled with archive doc pruned" {
    write_backlog \
        "# Backlog" \
        "" \
        "- TUNE-0004 · cancelled · P3 · L1 · Cancelled thing → tasks/TUNE-0004-task-description.md"
    make_archive "cancelled" "TUNE-0004"

    run "$SCRIPT" --root "$KB" --fix
    [ "$status" -eq 0 ]
    run grep -q "TUNE-0004" "$KB/datarim/backlog.md"
    [ "$status" -ne 0 ]
}

# ---------- (b) terminal + NO archive doc → PRESERVED + surfaced ----------

@test "(b) terminal entry without archive doc preserved and surfaced" {
    write_backlog \
        "# Backlog" \
        "" \
        "- TUNE-0010 · done · P2 · L1 · Unarchived task → tasks/TUNE-0010-task-description.md"
    # intentionally NO archive doc

    run "$SCRIPT" --root "$KB" --fix
    [ "$status" -eq 0 ]
    # capture script output before running grep (grep resets $output)
    script_output="$output"
    # entry must still be in backlog (data-loss-safe)
    run grep -q "TUNE-0010" "$KB/datarim/backlog.md"
    [ "$status" -eq 0 ]
    # surfaced signal must be emitted by the script
    [[ "$script_output" == *"surfaced:"* ]] || [[ "$script_output" == *"TUNE-0010"* ]]
}

@test "(b) --check also surfaces terminal entries without archive doc" {
    write_backlog \
        "# Backlog" \
        "" \
        "- INFRA-0020 · archived · P3 · L2 · Missing archive → tasks/INFRA-0020-task-description.md"

    run "$SCRIPT" --root "$KB" --check
    [ "$status" -eq 0 ]
    [[ "$output" == *"surfaced"* ]]
    # backlog untouched
    run grep -q "INFRA-0020" "$KB/datarim/backlog.md"
    [ "$status" -eq 0 ]
}

# ---------- (c) pending / blocked-pending → never touched ----------

@test "(c) pending entry never removed" {
    write_backlog \
        "# Backlog" \
        "" \
        "- TUNE-0030 · pending · P2 · L2 · Active work → tasks/TUNE-0030-task-description.md"

    run "$SCRIPT" --root "$KB" --fix
    [ "$status" -eq 0 ]
    run grep -q "TUNE-0030" "$KB/datarim/backlog.md"
    [ "$status" -eq 0 ]
}

@test "(c) blocked-pending entry never removed" {
    write_backlog \
        "# Backlog" \
        "" \
        "- TUNE-0031 · blocked-pending · P1 · L3 · Blocked task → tasks/TUNE-0031-task-description.md"

    run "$SCRIPT" --root "$KB" --fix
    [ "$status" -eq 0 ]
    run grep -q "TUNE-0031" "$KB/datarim/backlog.md"
    [ "$status" -eq 0 ]
}

@test "(c) cancelled (transient, no archive doc) kept as-is" {
    # A 'cancelled' entry that has no corresponding archive doc is transient —
    # it stays in backlog.md (canon allows transient cancelled entries).
    write_backlog \
        "# Backlog" \
        "" \
        "- TUNE-0032 · cancelled · P3 · L1 · Transient cancel → tasks/TUNE-0032-task-description.md"
    # NO archive doc → transient cancelled; must not be pruned without archive

    run "$SCRIPT" --root "$KB" --fix
    [ "$status" -eq 0 ]
    # preserved (no archive doc → surfaced, not silently dropped)
    run grep -q "TUNE-0032" "$KB/datarim/backlog.md"
    [ "$status" -eq 0 ]
}

# ---------- edge cases ----------

@test "empty backlog.md exits 0 cleanly" {
    printf '' > "$KB/datarim/backlog.md"

    run "$SCRIPT" --root "$KB" --check
    [ "$status" -eq 0 ]
}

@test "missing backlog.md exits 0 (no-op)" {
    # backlog.md doesn't exist — nothing to prune
    run "$SCRIPT" --root "$KB" --check
    [ "$status" -eq 0 ]
}

@test "usage error: no --check or --fix exits non-zero" {
    run "$SCRIPT" --root "$KB"
    [ "$status" -ne 0 ]
}
