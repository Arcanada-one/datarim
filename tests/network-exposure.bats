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

# --- Fix A: specific public + RFC1918 + link-local IPv4 → tier3_public ---
@test "compose: specific public IPv4 without justification fails (was malformed)" {
    run_lint --compose "$F/compose-fail-public-ipv4.yml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Tier 3 public"* ]]
}

@test "compose: specific public IPv4 with justification + TTL passes" {
    run_lint --compose "$F/compose-pass-public-ipv4-justified.yml"
    [ "$status" -eq 0 ]
}

@test "compose: RFC1918 10/8 without justification fails" {
    run_lint --compose "$F/compose-fail-rfc1918-8.yml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Tier 3 public"* ]]
}

@test "compose: RFC1918 172.16/12 with justification + TTL passes" {
    run_lint --compose "$F/compose-pass-rfc1918-12-justified.yml"
    [ "$status" -eq 0 ]
}

@test "compose: RFC1918 192.168/16 without justification fails" {
    run_lint --compose "$F/compose-fail-rfc1918-16.yml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Tier 3 public"* ]]
}

@test "compose: link-local 169.254/16 without justification fails" {
    run_lint --compose "$F/compose-fail-linklocal.yml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Tier 3 public"* ]]
}

@test "runtime-bind: specific public IPv4 classified tier3 (exit 1)" {
    run "$SCRIPT" --runtime-bind "203.0.113.10:443"
    [ "$status" -eq 1 ]
    [[ "$output" == *"tier3"* ]]
}

@test "runtime-bind: RFC1918 192.168 classified tier3 (exit 1)" {
    run "$SCRIPT" --runtime-bind "192.168.1.50:5432"
    [ "$status" -eq 1 ]
    [[ "$output" == *"tier3"* ]]
}

# --- Fix A regression: loopback/tailscale unchanged ---
@test "runtime-bind: 127.0.0.1 still tier1 (regression)" {
    run "$SCRIPT" --runtime-bind "127.0.0.1:8080"
    [ "$status" -eq 0 ]
    [[ "$output" == *"tier1"* ]]
}

@test "runtime-bind: Tailscale 100.64 still tier2 (regression)" {
    run "$SCRIPT" --runtime-bind "100.64.1.2:8080"
    [ "$status" -eq 0 ]
    [[ "$output" == *"tier2"* ]]
}

# --- Fix B: compose ${VAR} interpolation (B3 hybrid) ---
@test "compose: \${VAR:?} resolves from env to mesh IP → tier2 pass" {
    TAILNET_IP="100.64.7.8" run_lint --compose "$F/compose-var-required-mesh.yml"
    [ "$status" -eq 0 ]
}

@test "compose: \${VAR:?} resolves from env to public IP → tier3 fail" {
    TAILNET_IP="203.0.113.10" run_lint --compose "$F/compose-var-required-mesh.yml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Tier 3 public"* ]]
}

@test "compose: \${VAR:?} unresolved (no env) → WARN-but-PASS exit 0" {
    run_lint --compose "$F/compose-var-required-mesh.yml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unresolved"* ]] || [[ "$output" == *"TAILNET_IP"* ]]
}

@test "compose: \${VAR:-default} default-extract public → fail" {
    run_lint --compose "$F/compose-var-default-public.yml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Tier 3 public"* ]]
}

@test "compose: \${VAR:-default} default-extract loopback → pass" {
    run_lint --compose "$F/compose-var-default-loopback.yml"
    [ "$status" -eq 0 ]
}

@test "compose: bare \${VAR} unresolved (no env) → WARN-but-PASS exit 0" {
    run_lint --compose "$F/compose-var-bare.yml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unresolved"* ]] || [[ "$output" == *"BIND_HOST"* ]]
}

@test "compose: bare \${VAR} resolves from env to public → fail" {
    BIND_HOST="203.0.113.10" run_lint --compose "$F/compose-var-bare.yml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Tier 3 public"* ]]
}

# --- Fix B security: no eval, regex-validated var name, injection inert ---
@test "compose: \${VAR:?\$(id)} injection does not execute command" {
    rm -f /tmp/network-exposure-injection-canary
    run_lint --compose "$F/compose-var-injection.yml"
    [ ! -f /tmp/network-exposure-injection-canary ]
    [ "$status" -ne 0 ]
}

@test "compose: malformed var name rejected by regex gate" {
    run_lint --compose "$F/compose-var-badname.yml"
    [ "$status" -ne 0 ]
}

@test "script contains no eval or indirect-expansion of compose input" {
    run grep -nE 'eval|\$\{!' "$SCRIPT"
    [ "$status" -ne 0 ]
}
