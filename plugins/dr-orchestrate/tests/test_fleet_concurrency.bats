#!/usr/bin/env bats
# test_fleet_concurrency.bats — basic concurrency: per-task lock + cap enforce (3b).

setup() {
    PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export DR_ORCH_DIR="$PLUGIN_ROOT"
    REPO="$(cd "$PLUGIN_ROOT/../.." && pwd)"
    export DR_FLEET_REPO="$REPO"
    CONC="$PLUGIN_ROOT/scripts/fleet_concurrency.sh"
    export DR_FLEET_LOCK_DIR="$BATS_TEST_TMPDIR/locks"
    export DR_FLEET_STATE_DIR="$BATS_TEST_TMPDIR/sessions"
    mkdir -p "$DR_FLEET_LOCK_DIR" "$DR_FLEET_STATE_DIR"
}

@test "fleet_concurrency.sh exists and is executable" {
    [ -x "$CONC" ]
}

@test "fleet_acquire_lock succeeds once, then blocks the same task (mkdir-atomic)" {
    run bash "$CONC" fleet_acquire_lock job-1
    [ "$status" -eq 0 ]
    # second acquire for the same task must fail (lock held)
    run bash "$CONC" fleet_acquire_lock job-1
    [ "$status" -ne 0 ]
}

@test "fleet_release_lock frees the lock so it can be re-acquired" {
    bash "$CONC" fleet_acquire_lock job-2
    bash "$CONC" fleet_release_lock job-2
    run bash "$CONC" fleet_acquire_lock job-2
    [ "$status" -eq 0 ]
}

@test "different tasks acquire independent locks" {
    run bash "$CONC" fleet_acquire_lock job-a
    [ "$status" -eq 0 ]
    run bash "$CONC" fleet_acquire_lock job-b
    [ "$status" -eq 0 ]
}

@test "fleet_cap_check reads max_parallel from roles.yaml for a role" {
    # architect has max_parallel: 2 in the seed roles.yaml
    run bash "$CONC" fleet_cap_check architect 1
    [ "$status" -eq 0 ]   # 1 active < cap 2 → allowed
}

@test "fleet_cap_check rejects when active count reaches the role cap" {
    # architect cap = 2; 2 active → (cap+1)th rejected
    run bash "$CONC" fleet_cap_check architect 2
    [ "$status" -ne 0 ]   # 2 active >= cap 2 → blocked
}

@test "fleet_cap_check rejects beyond global_max_parallel regardless of role" {
    # global cap = 8; 8 active → blocked even if role cap is higher
    run bash "$CONC" fleet_cap_check developer 8
    [ "$status" -ne 0 ]
}

@test "fleet_cap_check unknown role fails closed" {
    run bash "$CONC" fleet_cap_check no-such-role 0
    [ "$status" -ne 0 ]
}
