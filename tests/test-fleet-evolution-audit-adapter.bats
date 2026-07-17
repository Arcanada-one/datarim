#!/usr/bin/env bats
# tests/test-fleet-evolution-audit-adapter.bats — audit-log source adapter +
# redaction layer (the third source-adapter for the skill-evolution loop).

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    ADAPTER="$REPO/plugins/dr-fleet-evolution/adapters/audit-log-adapter.sh"
    FIX="$REPO/tests/fixtures/fleet-evolution/audit"
    TMP="$BATS_TEST_TMPDIR"
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq not available — adapters require jq for JSONL emission"
    fi
}

@test "audit-log-adapter emits valid contract JSONL for fixtures" {
    run "$ADAPTER" "$FIX"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c .)" -eq 3 ]
    printf '%s\n' "$output" | while IFS= read -r l; do
        printf '%s' "$l" | jq -e 'has("task_input") and has("expected_output") and has("actual_output") and has("outcome") and .source=="audit-log"'
    done
}

@test "outcome is derived: success on ok trace, failure on denied/non-zero" {
    run "$ADAPTER" "$FIX"
    [ "$status" -eq 0 ]
    # deploy (success) + git status (exit 0) => 2 success; fetch (denied) => 1 failure.
    n_success=$(printf '%s\n' "$output" | jq -r 'select(.outcome=="success") | .outcome' | grep -c success)
    n_failure=$(printf '%s\n' "$output" | jq -r 'select(.outcome=="failure") | .outcome' | grep -c failure)
    [ "$n_success" -eq 2 ]
    [ "$n_failure" -eq 1 ]
}

@test "REDACTION: no sensitive token from an audit trace reaches the dataset" {
    run "$ADAPTER" "$FIX"
    [ "$status" -eq 0 ]
    # Capture the dataset before any inner grep (a nested `run` would clobber
    # $output).
    dataset="$output"
    # Secrets (key=value + bearer), absolute paths, IPs, user@host, and FQDN
    # hostnames present in the fixture MUST all be gone from the emitted dataset.
    for tok in "fake_key" "fake-host.internal" "203.0.113.7" "EXAMPLEpw" \
               "EXAMPLEbearer" "EXAMPLEkey" "user@fake-host" "/home/nobody"; do
        if printf '%s' "$dataset" | grep -qF "$tok"; then
            echo "LEAKED sensitive token: $tok" >&2
            false
        fi
    done
    # And a typed placeholder must be present, proving redaction ran (not just
    # that the fixture happened to omit the token).
    printf '%s' "$dataset" | grep -qE '<REDACTED>|<PATH>|<HOST>|<USER@HOST>'
}

@test "empty audit dir is success with empty stdout (not an error)" {
    mkdir -p "$TMP/empty"
    run "$ADAPTER" "$TMP/empty"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "DR_FLEET_AUDIT_REDIS=1 skips cleanly when redis-cli is absent" {
    if command -v redis-cli >/dev/null 2>&1; then
        skip "redis-cli present — cannot exercise the absent-redis skip path"
    fi
    mkdir -p "$TMP/empty"
    run env DR_FLEET_AUDIT_REDIS=1 "$ADAPTER" "$TMP/empty"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "missing directory is exit 1; no argument is exit 2" {
    run "$ADAPTER" "$TMP/does-not-exist"
    [ "$status" -eq 1 ]
    run "$ADAPTER"
    [ "$status" -eq 2 ]
}
