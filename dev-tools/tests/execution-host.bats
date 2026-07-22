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

    # --- TUNE-0507 canon fixtures -------------------------------------------
    # A workspace that carries a git-tracked spaces/ tree with a canonical
    # execution block, so canon-fallback (cache miss -> canon) can resolve it.
    CANON_WS="$TEST_TMP/canon-repo"
    mkdir -p "$CANON_WS/datarim" "$CANON_WS/spaces/demospace"
    cat > "$CANON_WS/spaces/registry.yml" <<EOF
registry:
  - name: demospace
    path: spaces/demospace/space.yml
    status: active
    role: root-managing
EOF
    cat > "$CANON_WS/spaces/demospace/space.yml" <<EOF
schema_version: 1
execution:
  required_host: canon-host
  host_aliases: [canon-host, Canon-Host]
  tailscale_ip: "100.99.0.7"
  ssh_user: dev
  default_agent: claude-code
  allowed_agents: [claude-code, codex, cursor]
EOF

    # A workspace with spaces/ but NO execution mandate anywhere (truly
    # unconfigured — canon-fallback must stay fail-open).
    NOMANDATE_WS="$TEST_TMP/nomandate-repo"
    mkdir -p "$NOMANDATE_WS/datarim" "$NOMANDATE_WS/spaces/plain"
    cat > "$NOMANDATE_WS/spaces/registry.yml" <<EOF
registry:
  - name: plain
    path: spaces/plain/space.yml
    status: active
    role: root-managing
EOF
    printf 'schema_version: 1\nname: plain\n' > "$NOMANDATE_WS/spaces/plain/space.yml"

    # Empty map path (cache absent — the arcana-devs trap condition).
    ABSENT_MAP="$TEST_TMP/no-such-cache.yml"
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

# ===========================================================================
# TUNE-0507 — canon-fallback + intent-aware fail-closed
# ===========================================================================

# --- eh_canon_space_for_root -----------------------------------------------

@test "eh_canon_space_for_root: resolves the root-managing space + canon path" {
    run bash -c "source '$LIB'; eh_canon_space_for_root '$CANON_WS'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"spaces/demospace/space.yml"* ]]
    [[ "$output" == *"demospace"* ]]
}

@test "eh_canon_space_for_root: no spaces/registry.yml returns 1" {
    run bash -c "source '$LIB'; eh_canon_space_for_root '$BOUND_WS'"
    [ "$status" -eq 1 ]
}

# --- eh_lookup_binding_canon -----------------------------------------------

@test "eh_lookup_binding_canon: reads canon execution block into the 7-field shape" {
    run bash -c "source '$LIB'; eh_lookup_binding_canon '$CANON_WS'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"canon-host"* ]]
    [[ "$output" == *"100.99.0.7"* ]]
    [[ "$output" == *"demospace"* ]]
    tabs=$(printf '%s' "$output" | tr -cd '\t' | wc -c | tr -d ' ')
    [ "$tabs" -eq 6 ]
}

@test "eh_lookup_binding_canon: canon with no execution mandate returns 1" {
    run bash -c "source '$LIB'; eh_lookup_binding_canon '$NOMANDATE_WS'"
    [ "$status" -eq 1 ]
}

# --- eh_canon_mandate_present (yq-free) ------------------------------------

@test "eh_canon_mandate_present: true when a space.yml carries an execution block" {
    run bash -c "source '$LIB'; eh_canon_mandate_present '$CANON_WS'"
    [ "$status" -eq 0 ]
}

@test "eh_canon_mandate_present: false when no space.yml carries a mandate" {
    run bash -c "source '$LIB'; eh_canon_mandate_present '$NOMANDATE_WS'"
    [ "$status" -eq 1 ]
}

@test "eh_canon_mandate_present: works without yq (grep-only probe)" {
    run bash -c "
      source '$LIB'
      command() { if [ \"\$1\" = -v ] && [ \"\$2\" = yq ]; then return 1; fi; builtin command \"\$@\"; }
      export -f command
      eh_canon_mandate_present '$CANON_WS'
    "
    [ "$status" -eq 0 ]
}

# --- eh_classify_intent ----------------------------------------------------

@test "eh_classify_intent: /dr-status is readonly" {
    run bash -c "source '$LIB'; eh_classify_intent 'claude /dr-status TUNE-1'"
    [ "$output" = "readonly" ]
}

@test "eh_classify_intent: /dr-do is mutating" {
    run bash -c "source '$LIB'; eh_classify_intent 'claude /dr-do TUNE-1'"
    [ "$output" = "mutating" ]
}

@test "eh_classify_intent: unknown/opaque command defaults to mutating" {
    run bash -c "source '$LIB'; eh_classify_intent 'codex'"
    [ "$output" = "mutating" ]
}

# --- eh_decision_intent ----------------------------------------------------

@test "eh_decision_intent: ARCANA-DEVS TRAP — cache absent + canon on-host + mutating -> ALLOW (0)" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='canon-host' eh_decision_intent '$CANON_WS' '$ABSENT_MAP' mutating"
    [ "$status" -eq 0 ]
}

@test "eh_decision_intent: cache absent + canon off-host + mutating -> off-host (10)" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='some-mac' eh_decision_intent '$CANON_WS' '$ABSENT_MAP' mutating"
    [ "$status" -eq 10 ]
}

@test "eh_decision_intent: off-host + read-only stays fail-open (0) even via canon" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='some-mac' eh_decision_intent '$CANON_WS' '$ABSENT_MAP' readonly"
    [ "$status" -eq 0 ]
}

@test "eh_decision_intent: truly unconfigured (no canon mandate) + mutating -> fail-open (0)" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='some-mac' eh_decision_intent '$NOMANDATE_WS' '$ABSENT_MAP' mutating"
    [ "$status" -eq 0 ]
}

@test "eh_decision_intent: mandate exists + yq absent + mutating -> fail-CLOSED (3)" {
    run bash -c "
      source '$LIB'
      yq() { return 127; }
      command() { if [ \"\$1\" = -v ] && [ \"\$2\" = yq ]; then return 1; fi; builtin command \"\$@\"; }
      export -f yq command
      EH_TEST_HOSTNAME='canon-host' eh_decision_intent '$CANON_WS' '$ABSENT_MAP' mutating
    "
    [ "$status" -eq 3 ]
}

@test "eh_decision_intent: mandate exists + yq absent + read-only -> fail-open (0)" {
    run bash -c "
      source '$LIB'
      yq() { return 127; }
      command() { if [ \"\$1\" = -v ] && [ \"\$2\" = yq ]; then return 1; fi; builtin command \"\$@\"; }
      export -f yq command
      EH_TEST_HOSTNAME='canon-host' eh_decision_intent '$CANON_WS' '$ABSENT_MAP' readonly
    "
    [ "$status" -eq 0 ]
}

@test "eh_decision_intent: malformed cache map + mutating -> fail-CLOSED (3)" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='some-mac' eh_decision_intent '$BOUND_WS' '$MALFORMED_MAP' mutating"
    [ "$status" -eq 3 ]
}

@test "eh_decision_intent: cache hit + host matches -> on-host (0)" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='test-host' eh_decision_intent '$BOUND_WS' '$MAP' mutating"
    [ "$status" -eq 0 ]
}

@test "eh_decision_intent: cache hit + host does not match + mutating -> off-host (10)" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='some-mac' eh_decision_intent '$BOUND_WS' '$MAP' mutating"
    [ "$status" -eq 10 ]
}
