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

# TUNE-0123: TAILNET_IP is a tailnet-mesh var name; unresolved → Tier 2 pass
# (mesh var-name recognition), NOT the anonymous residual WARN. See the dedicated
# residual coverage below (compose-var-residual-nonmesh.yml) for the WARN path.
@test "compose: \${TAILNET_IP:?} unresolved (no env) → tier2 mesh var-name pass" {
    run "$SCRIPT" --compose "$F/compose-var-required-mesh.yml" --today "$TODAY" --verbose
    [ "$status" -eq 0 ]
    [[ "$output" == *"tier2"* ]]
    [[ "$output" == *"TAILNET_IP"* ]]
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

# --- TUNE-0122: ${VAR:-N} interpolation in a PORT segment (not just host) ---
# The published/target port slot may hold ${VAR:-N}; the interpolation must
# resolve the effective port and then apply Tier rules to the (real) host.

@test "TUNE-0122: \${PORT:-N} in published-port slot, loopback host → tier1 pass" {
    # 127.0.0.1:${PORT:-3700}:3700 → 127.0.0.1:3700:3700 → tier1
    unset PORT
    run_lint --compose "$F/compose-var-portpos-hostok.yml"
    [ "$status" -eq 0 ]
}

@test "TUNE-0122: \${PORT:-N} short-form (no host) resolves default → Tier 3 short-form fail" {
    # ${PORT:-3700}:3700 → 3700:3700 → implicit 0.0.0.0 short-form (NOT unrecognized)
    unset PORT
    run_lint --compose "$F/compose-var-portpos-shortform.yml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"short-form"* ]]
    [[ "$output" != *"unrecognized"* ]]
}

@test "TUNE-0122: \${VAR} in port slot resolved from env, loopback host → tier1 pass" {
    HOST_PORT="3700" run_lint --compose "$F/compose-var-portpos-env.yml"
    [ "$status" -eq 0 ]
}

# --- TUNE-0123: ${TAILSCALE_IP}:PORT:PORT recognized as Tier 2 (mesh-bound) ---

@test "TUNE-0123: bare \${TAILSCALE_IP} host (unset) → tier2 pass, no unrecognized/WARN" {
    run "$SCRIPT" --compose "$F/compose-var-tailscale-host.yml" --today "$TODAY" --verbose
    [ "$status" -eq 0 ]
    [[ "$output" == *"tier2"* ]]
    [[ "$output" != *"unrecognized"* ]]
    [[ "$output" != *"WARN"* ]]
}

@test "TUNE-0123: \${TAILSCALE_IP} resolved from env to real mesh IP → tier2 pass" {
    TAILSCALE_IP="100.100.1.1" run_lint --compose "$F/compose-var-tailscale-host.yml"
    [ "$status" -eq 0 ]
}

@test "TUNE-0123: mesh var-name does NOT swallow a public env value → tier3 fail" {
    # A tailnet-named var pointing at a public IP is still classified by its
    # resolved value when env IS set — name recognition is only the unset fallback.
    TAILSCALE_IP="203.0.113.10" run_lint --compose "$F/compose-var-tailscale-host.yml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Tier 3 public"* ]]
}

@test "TUNE-0123 residual: non-mesh required var (unset) → B3 WARN-but-PASS" {
    # \${CUSTOM_BIND:?} is NOT a tailnet name → residual WARN path preserved.
    run_lint --compose "$F/compose-var-residual-nonmesh.yml"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unresolved"* ]] || [[ "$output" == *"CUSTOM_BIND"* ]]
}

# --- Fix B: protocol suffix (/udp /tcp /sctp) on long-form host:port:port ---
@test "compose: Tailscale-IP DNS with /udp /tcp suffix passes tier2" {
    run_lint --compose "$F/compose-pass-coredns-proto.yml"
    [ "$status" -eq 0 ]
}

# --- Fix C: long-form port object (docker compose config shape) ---
@test "compose: long-form object loopback passes tier1" {
    run_lint --compose "$F/compose-pass-longform-loopback.yml"
    [ "$status" -eq 0 ]
}

@test "compose: long-form object public + justification passes" {
    run_lint --compose "$F/compose-pass-longform-justified.yml"
    [ "$status" -eq 0 ]
}

@test "compose: long-form object without host_ip fails (implicit 0.0.0.0)" {
    run_lint --compose "$F/compose-fail-longform-no-hostip.yml"
    [ "$status" -eq 1 ]
}
