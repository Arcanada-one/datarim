#!/usr/bin/env bats
# Tests for dev-tools/check-execution-host-health.sh
#
# The script exists because exit 0 from the resolver means both «gated and
# passing» and «not gated at all». It answers the question the exit code
# cannot: is this machine ACTUALLY protected? It never infers health from
# silence -- it forces the deny path with a foreign hostname and requires
# that deny to happen.
#
# So the tests here must prove the script FAILS when it should. A health
# check that cannot go red is the very defect it is meant to detect.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/dev-tools/check-execution-host-health.sh"

setup() {
    TEST_TMP="$(mktemp -d)"
    BOUND_WS="$TEST_TMP/bound-repo"
    UNBOUND_WS="$TEST_TMP/unbound-repo"
    mkdir -p "$BOUND_WS/datarim" "$UNBOUND_WS/datarim"

    MAP="$TEST_TMP/execution-hosts.yml"
    cat > "$MAP" <<EOF
schema_version: 1
role: control
bindings:
  - workspace: $BOUND_WS
    space: testspace
    required_host: test-host
    host_aliases: [test-host]
    tailscale_ip: "100.64.0.42"
    ssh_user: dev
    default_agent: claude-code
    allowed_agents: [claude-code]
EOF
    ABSENT_MAP="$TEST_TMP/no-such-map.yml"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# --- the gated cases ---------------------------------------------------------

@test "health: on the declared host, both controls agree -> OK, exit 0" {
    run env EH_TEST_HOSTNAME=test-host bash "$SCRIPT" --check --root "$BOUND_WS" --map "$MAP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK: gated"* ]]
}

@test "health: on a foreign host with a real binding -> correctly off-host, exit 0" {
    run env EH_TEST_HOSTNAME=some-laptop bash "$SCRIPT" --check --root "$BOUND_WS" --map "$MAP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"correctly off-host"* ]]
}

# --- the case that hid the outage -------------------------------------------

@test "health: unconfigured workspace says so OUT LOUD, never silently 'fine'" {
    # This is the whole point. A machine with no binding must not read as
    # healthy -- it must announce that it is not gated.
    run env EH_TEST_HOSTNAME=test-host bash "$SCRIPT" --check --root "$UNBOUND_WS" --map "$MAP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"UNCONFIGURED"* ]]
    [[ "$output" == *"NOT gated"* ]]
}

@test "health: a missing routing map reports unconfigured, not a passing gate" {
    run env EH_TEST_HOSTNAME=test-host bash "$SCRIPT" --check --root "$BOUND_WS" --map "$ABSENT_MAP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"UNCONFIGURED"* ]]
    [[ "$output" != *"OK: gated"* ]]
}

# --- MUTATION CONTROL: prove the check can actually go red ------------------

@test "health: MIS-GATED when the negative control fails to deny (mutation)" {
    # Seed the exact regression the script guards against: a resolver whose
    # negative control does NOT deny. If this passes, the health check is
    # decorative. Stub the library so eh_decision always claims on-host.
    local fake_lib_dir="$TEST_TMP/fake/dev-tools/lib"
    mkdir -p "$fake_lib_dir"
    cp "$SCRIPT" "$TEST_TMP/fake/dev-tools/"
    cat > "$fake_lib_dir/execution-host.sh" <<'EOF'
eh_resolve_workspace_root() { printf '%s' "$1"; return 0; }
eh_decision() { EH_STATE="on-host"; return 0; }
EOF
    run env EH_TEST_HOSTNAME=anything bash "$TEST_TMP/fake/dev-tools/check-execution-host-health.sh" \
        --check --root "$BOUND_WS" --map "$MAP"
    [ "$status" -eq 1 ]
    [[ "$output" == *"MIS-GATED"* ]]
}

@test "health: MIS-GATED when a mandate resolves inconsistently (mutation)" {
    # positive=unconfigured while negative=off-host: a binding exists but the
    # current host cannot be resolved against it. Precisely the shape of a
    # half-wired machine.
    local fake_lib_dir="$TEST_TMP/fake2/dev-tools/lib"
    mkdir -p "$fake_lib_dir"
    cp "$SCRIPT" "$TEST_TMP/fake2/dev-tools/"
    cat > "$fake_lib_dir/execution-host.sh" <<'EOF'
eh_resolve_workspace_root() { printf '%s' "$1"; return 0; }
eh_decision() {
    if [ "${EH_TEST_HOSTNAME:-}" = "eh-health-probe-not-a-real-host.invalid" ]; then
        EH_STATE="off-host"; return 10
    fi
    EH_STATE="unconfigured"; return 0
}
EOF
    run bash "$TEST_TMP/fake2/dev-tools/check-execution-host-health.sh" \
        --check --root "$BOUND_WS" --map "$MAP"
    [ "$status" -eq 1 ]
    [[ "$output" == *"MIS-GATED"* ]]
}

# --- environment / usage: must fail closed ----------------------------------

@test "health: missing resolver library is an error, NOT a pass" {
    local d="$TEST_TMP/nolib/dev-tools"
    mkdir -p "$d"
    cp "$SCRIPT" "$d/"
    run bash "$d/check-execution-host-health.sh" --check --root "$BOUND_WS" --map "$MAP"
    [ "$status" -eq 2 ]
}

@test "health: unresolvable workspace root exits 2, never 0" {
    run bash "$SCRIPT" --check --root "$TEST_TMP/does-not-exist" --map "$MAP"
    [ "$status" -eq 2 ]
}

@test "health: unknown argument exits 2 with usage" {
    run bash "$SCRIPT" --bogus
    [ "$status" -eq 2 ]
}

@test "health: --report prints both controls by name" {
    run env EH_TEST_HOSTNAME=test-host bash "$SCRIPT" --report --root "$BOUND_WS" --map "$MAP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"positive control"* ]]
    [[ "$output" == *"negative control"* ]]
}
