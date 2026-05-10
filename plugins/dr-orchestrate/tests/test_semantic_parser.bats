#!/usr/bin/env bats
# test_semantic_parser.bats — V-AC 14

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
}

@test "V-AC-14: parser yields confidence > 0 for known /dr- command" {
    out=$(bash "$DR_ORCH_DIR/scripts/semantic_parser.sh" parse "/dr-plan TUNE-0164")
    echo "$out" | jq -e '.confidence > 0'
}

@test "V-AC-14: parser yields confidence == 0 for unknown text" {
    out=$(bash "$DR_ORCH_DIR/scripts/semantic_parser.sh" parse "garbage input")
    echo "$out" | jq -e '.confidence == 0'
}

@test "V-AC-14: parser preserves the original input verbatim in command field" {
    out=$(bash "$DR_ORCH_DIR/scripts/semantic_parser.sh" parse "/dr-archive TUNE-0164")
    [ "$(echo "$out" | jq -r '.command')" = "/dr-archive TUNE-0164" ]
}

@test "V-AC-14: parser source field marks Phase 1 stub" {
    out=$(bash "$DR_ORCH_DIR/scripts/semantic_parser.sh" parse "/dr-do")
    [ "$(echo "$out" | jq -r '.source')" = "rule_phase1_stub" ]
}
