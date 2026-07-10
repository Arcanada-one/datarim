#!/usr/bin/env bats
#
# bats spec for dev-tools/sha-bridge-audit.sh (INFRA-0202). Sources the
# script (guarded so `main` does not auto-run) to unit-test the
# network-independent state_get/state_set/emit_event functions in
# isolation. Live-network state-machine behaviour is smoke-tested manually
# against the real Arcanada-one/datarim repo (see PR description).

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/sha-bridge-audit.sh"
    WORK="$(mktemp -d)"
    SHA_BRIDGE_STATE_FILE="$WORK/state"
    # shellcheck source=/dev/null
    source "$SCRIPT"
}

teardown() {
    rm -rf "$WORK"
}

# ---------------------------------------------------------------------------
# state_get / state_set — local-file fallback (no vault CLI / VAULT_ADDR)
# ---------------------------------------------------------------------------
@test "state-get-empty-when-unset — no state file yet returns empty" {
    run state_get "decommissioned_at"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "state-set-then-get-roundtrips — persisted field readable on next call" {
    state_set "window_opened_at" "2026-07-01T00:00:00Z"
    run state_get "window_opened_at"
    [ "$status" -eq 0 ]
    [ "$output" = "2026-07-01T00:00:00Z" ]
}

@test "state-fields-are-independent — decommissioned_at unaffected by window_opened_at" {
    state_set "window_opened_at" "2026-07-01T00:00:00Z"
    run state_get "decommissioned_at"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "state-set-no-backend-configured — warns but does not fail" {
    SHA_BRIDGE_STATE_FILE=""
    run state_set "decommissioned_at" "2026-07-01T00:00:00Z"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NOT persisted"* ]]
}

# ---------------------------------------------------------------------------
# emit_event — dry-run mode when OPS_BOT_API_KEY unset
# ---------------------------------------------------------------------------
@test "emit-event-dry-run — no OPS_BOT_API_KEY prints DRY-RUN, never calls curl" {
    OPS_BOT_API_KEY=""
    run emit_event "warning" "test-dedup-key" "test body"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN event:"* ]]
    [[ "$output" == *"test-dedup-key"* ]]
    [[ "$output" == *'"category":"warning"'* ]]
}

# ---------------------------------------------------------------------------
# defaults — sanity on the constants the escalation math depends on
# ---------------------------------------------------------------------------
@test "defaults-baked-sha-and-window — match the documented INFRA-0202 constants" {
    [ "$BAKED_SHA" = "4937a5ab622f125674871a87bcc88c9c7e1d4596" ]
    [ "$RETIREMENT_WINDOW_DAYS" -eq 7 ]
    [ "$REPO" = "Arcanada-one/datarim" ]
    [ "$PR_NUMBER" -eq 8 ]
    [ "$TAG_REF" = "v1" ]
}
