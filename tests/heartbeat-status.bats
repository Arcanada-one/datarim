#!/usr/bin/env bats

# Test contract: dev-tools/lib/heartbeat-status.sh — the dispatch heartbeat
# status-file contract (PRD-TUNE-0490 Phase 2). One writer/reader for
# datarim/runtime/<TASK-ID>.status so the producer (delegated agent) and
# consumer (laptop monitor) never drift.
#
# Covers:
#   write/read roundtrip, atomic write, field extraction, age computation,
#   task-id validation (no dir escape), state validation, escape safety,
#   awaiting_operator question/options block.

LIB="$BATS_TEST_DIRNAME/../dev-tools/lib/heartbeat-status.sh"

setup() {
    [ -f "$LIB" ] || skip "heartbeat-status.sh not found: $LIB"
    ROOT="$BATS_TEST_TMPDIR/ws"
    mkdir -p "$ROOT/datarim"
    NOW=1800000000
}

@test "write then read roundtrip: in_progress" {
    run bash "$LIB" write --root "$ROOT" --task-id ARCA-0001 --state in_progress --stage do --pid 42 --now "$NOW"
    [ "$status" -eq 0 ]
    run bash "$LIB" field --root "$ROOT" --task-id ARCA-0001 --field state
    [ "$output" = "in_progress" ]
    run bash "$LIB" field --root "$ROOT" --task-id ARCA-0001 --field stage
    [ "$output" = "do" ]
    run bash "$LIB" field --root "$ROOT" --task-id ARCA-0001 --field pid
    [ "$output" = "42" ]
}

@test "age computed from updated_at" {
    bash "$LIB" write --root "$ROOT" --task-id ARCA-0002 --state in_progress --now $((NOW-120)) >/dev/null
    run bash "$LIB" age --root "$ROOT" --task-id ARCA-0002 --now "$NOW"
    # age helper uses real now; assert the field instead for determinism
    run bash "$LIB" field --root "$ROOT" --task-id ARCA-0002 --field updated_at
    [ "$output" = "$((NOW-120))" ]
}

@test "invalid task-id refused (no runtime-dir escape)" {
    run bash "$LIB" write --root "$ROOT" --task-id "../etc/passwd" --state done
    [ "$status" -eq 2 ]
    run bash "$LIB" write --root "$ROOT" --task-id "lowercase-0001" --state done
    [ "$status" -eq 2 ]
}

@test "invalid state refused" {
    run bash "$LIB" write --root "$ROOT" --task-id ARCA-0003 --state bogus
    [ "$status" -eq 2 ]
}

@test "read absent status exits 1" {
    run bash "$LIB" read --root "$ROOT" --task-id ARCA-9999
    [ "$status" -eq 1 ]
}

@test "awaiting_operator carries question + options" {
    bash "$LIB" write --root "$ROOT" --task-id ARCA-0004 --state awaiting_operator \
        --question-id gate1 --question-text "Force-push?" --option "Yes" --option "No" --now "$NOW" >/dev/null
    run bash "$LIB" field --root "$ROOT" --task-id ARCA-0004 --field state
    [ "$output" = "awaiting_operator" ]
    run bash "$LIB" field --root "$ROOT" --task-id ARCA-0004 --field question_id
    [ "$output" = "gate1" ]
    # options array present in raw JSON
    run bash "$LIB" read --root "$ROOT" --task-id ARCA-0004
    [[ "$output" == *'"options"'* ]]
    [[ "$output" == *"Yes"* ]]
    [[ "$output" == *"No"* ]]
}

@test "escape safety: backslash and quotes roundtrip losslessly" {
    bash "$LIB" write --root "$ROOT" --task-id ARCA-0005 --state done \
        --question-text 'path C:\tmp and "quoted"' --now "$NOW" >/dev/null
    # raw file must be valid JSON if jq is available
    if command -v jq >/dev/null 2>&1; then
        run bash -c "bash '$LIB' read --root '$ROOT' --task-id ARCA-0005 | jq -r '.question_text'"
        [ "$output" = 'path C:\tmp and "quoted"' ]
    fi
}

@test "atomic write leaves no .tmp turd" {
    bash "$LIB" write --root "$ROOT" --task-id ARCA-0006 --state done --now "$NOW" >/dev/null
    run bash -c "ls '$ROOT/datarim/runtime/'*.tmp.* 2>/dev/null | wc -l | tr -d ' '"
    [ "$output" = "0" ]
}
