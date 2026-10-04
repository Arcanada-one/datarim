#!/usr/bin/env bats
setup() {
    DATARIM_CLI_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SUT="$DATARIM_CLI_DIR/subcommands/backlog.sh"
    [[ -f "$SUT" ]] || skip "subcommands/backlog.sh not yet implemented"
    FIX="$BATS_TMPDIR/wsr-$$"
    mkdir -p "$FIX/datarim"
    cat > "$FIX/datarim/backlog.md" <<'EOF'
# Backlog
- TUNE-1001 · pending · P3 · L1 · Idea A → tasks/TUNE-1001-task-description.md
- TUNE-1002 · pending · P3 · L2 · Idea B → tasks/TUNE-1002-task-description.md
- ARCA-1003 · deferred · P4 · L2 · Maybe later → tasks/ARCA-1003-task-description.md
EOF
}
teardown() { [[ -n "${FIX:-}" ]] && rm -rf "$FIX"; }

@test "1: list outputs 3 items" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"TUNE-1001"* ]]
    [[ "$output" == *"ARCA-1003"* ]]
    [[ "$output" == *"total: 3"* ]]
}
@test "2: --prefix TUNE returns 2 items" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" list --prefix TUNE
    [ "$status" -eq 0 ]
    [[ "$output" == *"TUNE-1001"* ]]
    [[ "$output" == *"TUNE-1002"* ]]
    [[ "$output" != *"ARCA-1003"* ]]
    [[ "$output" == *"total: 2"* ]]
}
@test "3: --json envelope with items + count + prefix" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT" list --prefix TUNE --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.command == "backlog list"' >/dev/null
    echo "$output" | jq -e '.data.count == 2' >/dev/null
    echo "$output" | jq -e '.data.prefix == "TUNE"' >/dev/null
}
@test "4: missing backlog.md → exit 31" {
    EMPTY="$BATS_TMPDIR/empty-$$"
    mkdir -p "$EMPTY/datarim"
    DATARIM_WORKSPACE_ROOT="$EMPTY" run "$SUT" list
    [ "$status" -eq 31 ]
    rm -rf "$EMPTY"
}
@test "5: no subcommand → exit 2" {
    DATARIM_WORKSPACE_ROOT="$FIX" run "$SUT"
    [ "$status" -eq 2 ]
}
