#!/usr/bin/env bats
# network-exposure-verifier.bats — TUNE-0295 Phase F V-AC-8
# Verifies dev-tools/network-exposure-check.sh --runtime-bind <addr:port>
# correctly classifies the dr-orchestrate listener as Tier 1 loopback.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../" && pwd)"
CHECK="$REPO_ROOT/dev-tools/network-exposure-check.sh"

@test "V-AC-8 §runtime-bind: 127.0.0.1:31415 classified Tier 1 (exit 0)" {
  run bash "$CHECK" --runtime-bind 127.0.0.1:31415
  [ "$status" -eq 0 ]
  [[ "$output" == *tier1* ]] || [[ "$output" == *"Tier 1"* ]] || [[ "$output" == *"loopback"* ]]
}

@test "V-AC-8 §runtime-bind: ::1 (IPv6 loopback) classified Tier 1" {
  run bash "$CHECK" --runtime-bind "[::1]:31415"
  [ "$status" -eq 0 ]
}

@test "V-AC-8 §runtime-bind: 0.0.0.0:31415 rejected as Tier 3 public (exit 1)" {
  run bash "$CHECK" --runtime-bind 0.0.0.0:31415
  [ "$status" -ne 0 ]
}

@test "V-AC-8 §runtime-bind: malformed addr returns exit 2 or 1" {
  run bash "$CHECK" --runtime-bind "not-an-addr"
  [ "$status" -ne 0 ]
}
