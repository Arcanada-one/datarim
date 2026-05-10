#!/usr/bin/env bats
# TUNE-0109 — network-exposure-check.sh fixture suite.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/dev-tools/network-exposure-check.sh"
    F="$REPO_ROOT/tests/fixtures/network-exposure"
    TODAY="2026-05-06"
}

run_lint() {
    run "$SCRIPT" "$@" --today "$TODAY"
}

# --- Compose pass cases ---
@test "compose: 127.0.0.1 bind passes" {
    run_lint --compose "$F/compose-pass-1270.yml"
    [ "$status" -eq 0 ]
}

@test "compose: justified 0.0.0.0 + valid TTL passes" {
    run_lint --compose "$F/compose-pass-justified.yml"
    [ "$status" -eq 0 ]
}

@test "compose: Tailscale 100.65.x.x passes" {
    run_lint --compose "$F/compose-pass-tailscale.yml"
    [ "$status" -eq 0 ]
}

@test "compose: IPv6 [::1] loopback passes" {
    run_lint --compose "$F/compose-pass-ipv6-loopback.yml"
    [ "$status" -eq 0 ]
}

# --- Compose fail cases ---
@test "compose: 0.0.0.0 without justification fails" {
    run_lint --compose "$F/compose-fail-0000.yml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Tier 3 public"* ]]
}

@test "compose: short-form 5432:5432 fails" {
    run_lint --compose "$F/compose-fail-short.yml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"short-form"* ]]
}

@test "compose: IPv6 [::] unspecified fails" {
    run_lint --compose "$F/compose-fail-ipv6.yml"
    [ "$status" -eq 1 ]
}

@test "compose: expired x-exposure-expires fails" {
    run_lint --compose "$F/compose-fail-expired.yml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"expired"* ]]
}

# --- Redis ---
@test "redis: bind 0.0.0.0 fails" {
    run_lint --redis-conf "$F/redis-fail.conf"
    [ "$status" -eq 1 ]
}

@test "redis: bind 127.0.0.1 ::1 passes" {
    run_lint --redis-conf "$F/redis-pass-loopback.conf"
    [ "$status" -eq 0 ]
}

# --- Postgres ---
@test "postgres: listen_addresses='*' fails" {
    run_lint --postgres-conf "$F/postgresql-fail.conf"
    [ "$status" -eq 1 ]
}

@test "postgres: listen_addresses='localhost' passes" {
    run_lint --postgres-conf "$F/postgresql-pass.conf"
    [ "$status" -eq 0 ]
}

# --- systemd ---
@test "systemd: ListenStream=0.0.0.0 fails" {
    run_lint --systemd-socket "$F/svc-fail.socket"
    [ "$status" -eq 1 ]
}

@test "systemd: ListenStream=127.0.0.1 passes" {
    run_lint --systemd-socket "$F/svc-pass.socket"
    [ "$status" -eq 0 ]
}

# --- usage / version ---
@test "version flag prints version" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"network-exposure-check.sh"* ]]
}

@test "unknown flag exits 2" {
    run "$SCRIPT" --bogus 1
    [ "$status" -eq 2 ]
}
