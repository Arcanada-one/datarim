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

@test "TUNE-0183: parser hits /dr-status from yaml rules" {
    out=$(bash "$DR_ORCH_DIR/scripts/semantic_parser.sh" parse "/dr-status")
    echo "$out" | jq -e '.confidence > 0'
}

@test "TUNE-0183: parser hits /dr-continue from yaml rules" {
    out=$(bash "$DR_ORCH_DIR/scripts/semantic_parser.sh" parse "/dr-continue ARCA-0034")
    echo "$out" | jq -e '.confidence > 0'
}

@test "TUNE-0183: parser hits /dr-design from yaml rules" {
    out=$(bash "$DR_ORCH_DIR/scripts/semantic_parser.sh" parse "/dr-design TUNE-0001")
    echo "$out" | jq -e '.confidence > 0'
}

@test "TUNE-0183: parser hits /dr-compliance from yaml rules" {
    out=$(bash "$DR_ORCH_DIR/scripts/semantic_parser.sh" parse "/dr-compliance TUNE-0001")
    echo "$out" | jq -e '.confidence > 0'
}

@test "TUNE-0183: parser picks highest confidence on multi-match (0.95 > 0.90)" {
    out=$(bash "$DR_ORCH_DIR/scripts/semantic_parser.sh" parse "echo /dr-status; echo /dr-plan TUNE-0001")
    conf=$(echo "$out" | jq -r '.confidence')
    awk -v c="$conf" 'BEGIN{exit !(c==0.95)}'
}
