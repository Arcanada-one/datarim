#!/usr/bin/env bats
# Tests for dev-tools/session-execution-drift-warn.sh (TUNE-0507).
# SessionStart ADVISORY: warns on drift/staleness/missing-cache, NEVER blocks,
# always exits 0. Space is derived from spaces/registry.yml (root-managing).

WARN="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/session-execution-drift-warn.sh"

setup() {
    TEST_TMP="$(mktemp -d)"
    ROOT="$TEST_TMP/ws"
    mkdir -p "$ROOT/datarim" "$ROOT/spaces/demospace"
    cat > "$ROOT/spaces/registry.yml" <<EOF
registry:
  - name: demospace
    path: spaces/demospace/space.yml
    role: root-managing
EOF
    cat > "$ROOT/spaces/demospace/space.yml" <<EOF
schema_version: 1
execution:
  required_host: canon-host
  host_aliases: [canon-host]
  tailscale_ip: "100.99.0.7"
  ssh_user: dev
  default_agent: claude-code
  allowed_agents: [claude-code]
EOF

    # Agreed cache (matches canon, fresh synced_at).
    AGREED_MAP="$TEST_TMP/agreed.yml"
    cat > "$AGREED_MAP" <<EOF
schema_version: 1
synced_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
bindings:
  - workspace: $ROOT
    space: demospace
    required_host: canon-host
    host_aliases: [canon-host]
    tailscale_ip: "100.99.0.7"
    ssh_user: dev
    default_agent: claude-code
    allowed_agents: [claude-code]
EOF

    # Drifted cache (required_host disagrees with canon).
    DRIFT_MAP="$TEST_TMP/drift.yml"
    cat > "$DRIFT_MAP" <<EOF
schema_version: 1
synced_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
bindings:
  - workspace: $ROOT
    space: demospace
    required_host: WRONG-host
    host_aliases: [WRONG-host]
    tailscale_ip: "100.99.0.7"
    ssh_user: dev
    default_agent: claude-code
    allowed_agents: [claude-code]
EOF

    ABSENT_MAP="$TEST_TMP/no-such-cache.yml"

    # A cwd not inside any datarim workspace.
    NON_WS="$TEST_TMP/plain"
    mkdir -p "$NON_WS"
}

teardown() { rm -rf "$TEST_TMP"; }

run_warn() {  # $1 = cwd, $2 = map path
    printf '{"hook_event_name":"SessionStart","cwd":"%s"}' "$1" \
        | DATARIM_EXEC_HOSTS_MAP="$2" bash "$WARN"
}

@test "agreed canon<->cache is silent (no advisory) and exits 0" {
    run run_warn "$ROOT" "$AGREED_MAP"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "drift (required_host mismatch) prints one advisory and exits 0" {
    run run_warn "$ROOT" "$DRIFT_MAP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"execution-host"* ]]
    [[ "$output" == *"drift"* ]]
    [[ "$output" == *"--fix"* ]]
}

@test "missing cache advises regeneration and exits 0" {
    run run_warn "$ROOT" "$ABSENT_MAP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"no machine-local routing cache"* ]]
    [[ "$output" == *"--fix"* ]]
}

@test "cwd outside any datarim workspace is silent and exits 0" {
    run run_warn "$NON_WS" "$AGREED_MAP"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "never blocks: always exits 0 even with a nonexistent canon path" {
    # Break canon by removing the space.yml; the script must still exit 0.
    rm -f "$ROOT/spaces/demospace/space.yml"
    run run_warn "$ROOT" "$DRIFT_MAP"
    [ "$status" -eq 0 ]
}
