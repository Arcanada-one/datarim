#!/usr/bin/env bats
# TUNE-0410 — additive-nullable-field schema-extension pattern documentation
# regression guard. Source: reflection-TUNE-0225 L2/B2 (spawned Class B).

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    AUDIT_SINK="$PLUGIN_ROOT/scripts/audit_sink.sh"
}

@test "audit_sink.sh header documents the additive-nullable-field pattern" {
    run grep -ci 'additive-nullable-field' "$AUDIT_SINK"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "pattern doc cites the expected_outcome precedent and no schema_version bump" {
    run grep -c 'expected_outcome' "$AUDIT_SINK"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
    run grep -ci 'without a schema_version bump\|no schema_version gate' "$AUDIT_SINK"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "make_event_v2 expected_outcome still yields null when unset (behaviour unchanged)" {
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    unset DR_ORCH_EXPECTED_OUTCOME
    # shellcheck disable=SC1090
    source "$AUDIT_SINK"
    run make_event_v2 "matched" "cmd" 0 10 "pane1" 0.9 "" "" "" "" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *'"expected_outcome":null'* ]]
}
