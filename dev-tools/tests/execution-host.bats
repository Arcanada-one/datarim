#!/usr/bin/env bats
# Tests for dev-tools/lib/execution-host.sh (TUNE-0472, Phase 2).
# Usage: bats dev-tools/tests/execution-host.bats
#
# Covers V-AC-1: shared framework-native execution-host resolver library.
# One resolver, two consumers (Step-0 in commands + machine-local guard).

LIB="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/dev-tools/lib/execution-host.sh"

setup() {
    TEST_TMP="$(mktemp -d)"
    BOUND_WS="$TEST_TMP/bound-repo"
    UNBOUND_WS="$TEST_TMP/unbound-repo"
    mkdir -p "$BOUND_WS/datarim" "$BOUND_WS/Projects/Sub"
    mkdir -p "$UNBOUND_WS/datarim"

    MAP="$TEST_TMP/execution-hosts.yml"
    cat > "$MAP" <<EOF
schema_version: 1
role: control
bindings:
  - workspace: $BOUND_WS
    space: testspace
    required_host: test-host
    host_aliases: [test-host, Test-Host]
    tailscale_ip: "100.64.0.42"
    ssh_user: dev
    default_agent: claude-code
    allowed_agents: [claude-code, codex, cursor]
EOF

    MALFORMED_MAP="$TEST_TMP/execution-hosts-malformed.yml"
    printf 'bindings: [this is not: valid: yaml: [[[\n' > "$MALFORMED_MAP"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# ---------------------------------------------------------------------------
# eh_resolve_workspace_root
# ---------------------------------------------------------------------------

@test "eh_resolve_workspace_root: finds root when cwd IS the root" {
    run bash -c "source '$LIB'; eh_resolve_workspace_root '$BOUND_WS'"
    [ "$status" -eq 0 ]
    [ "$output" = "$BOUND_WS" ]
}

@test "eh_resolve_workspace_root: finds root when cwd is a nested subdirectory" {
    run bash -c "source '$LIB'; eh_resolve_workspace_root '$BOUND_WS/Projects/Sub'"
    [ "$status" -eq 0 ]
    [ "$output" = "$BOUND_WS" ]
}

@test "eh_resolve_workspace_root: returns 1 when no ancestor has datarim/" {
    run bash -c "source '$LIB'; eh_resolve_workspace_root '/tmp'"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# eh_lookup_binding
# ---------------------------------------------------------------------------

@test "eh_lookup_binding: hit returns TAB-separated fields mirroring Phase-1 shape" {
    run bash -c "source '$LIB'; eh_lookup_binding '$BOUND_WS' '$MAP'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-host"* ]]
    [[ "$output" == *"100.64.0.42"* ]]
    [[ "$output" == *"dev"* ]]
    [[ "$output" == *"claude-code"* ]]
    [[ "$output" == *"testspace"* ]]
    # 7 TAB-separated fields (6 tabs).
    tabs=$(printf '%s' "$output" | tr -cd '\t' | wc -c | tr -d ' ')
    [ "$tabs" -eq 6 ]
}

@test "eh_lookup_binding: miss (workspace not in map) returns 1" {
    run bash -c "source '$LIB'; eh_lookup_binding '$UNBOUND_WS' '$MAP'"
    [ "$status" -eq 1 ]
}

@test "eh_lookup_binding: missing map file returns 1" {
    run bash -c "source '$LIB'; eh_lookup_binding '$BOUND_WS' '$TEST_TMP/nope.yml'"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# eh_host_match
# ---------------------------------------------------------------------------

@test "eh_host_match: matches by exact required_host (via hostname override)" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='test-host' eh_host_match 'test-host' 'test-host,Test-Host' '100.64.0.42'"
    [ "$status" -eq 0 ]
}

@test "eh_host_match: matches by alias" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='Test-Host' eh_host_match 'test-host' 'test-host,Test-Host' '100.64.0.42'"
    [ "$status" -eq 0 ]
}

@test "eh_host_match: matches by tailscale_ip" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='100.64.0.42' eh_host_match 'test-host' 'test-host,Test-Host' '100.64.0.42'"
    [ "$status" -eq 0 ]
}

@test "eh_host_match: no match returns 1" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='some-other-mac' eh_host_match 'test-host' 'test-host,Test-Host' '100.64.0.42'"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# eh_decision (orchestrator)
# ---------------------------------------------------------------------------

@test "eh_decision: unconfigured workspace (no binding) fail-opens (exit 0)" {
    run bash -c "source '$LIB'; eh_decision '$UNBOUND_WS' '$MAP'"
    [ "$status" -eq 0 ]
}

@test "eh_decision: bound workspace + host matches -> on-host, exit 0" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='test-host' eh_decision '$BOUND_WS' '$MAP'"
    [ "$status" -eq 0 ]
}

@test "eh_decision: bound workspace + host does not match -> off-host, exit 10" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='some-other-mac' eh_decision '$BOUND_WS' '$MAP'"
    [ "$status" -eq 10 ]
}

@test "eh_decision: malformed YAML map -> fail-closed, exit 3" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='some-other-mac' eh_decision '$BOUND_WS' '$MALFORMED_MAP'"
    [ "$status" -eq 3 ]
}

@test "eh_decision: yq missing -> degrade to unconfigured, exit 0 (fail-open, cannot read map)" {
    run bash -c "
      source '$LIB'
      yq() { return 127; }
      command() { if [ \"\$1\" = -v ] && [ \"\$2\" = yq ]; then return 1; fi; builtin command \"\$@\"; }
      export -f yq command
      eh_decision '$BOUND_WS' '$MAP'
    "
    [ "$status" -eq 0 ]
}

@test "eh_decision: sourcing the library has no side effects (no stdout, no file writes)" {
    run bash -c "source '$LIB'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
