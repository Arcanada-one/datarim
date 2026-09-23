#!/usr/bin/env bats

@test "receipt heartbeat rejects invalid consumption snapshots and preserves prior state" {
    run python3 "$BATS_TEST_DIRNAME/test_heartbeat_receipts.py"
    printf '%s\n' "$output"
    [ "$status" -eq 0 ]
}
