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

# ===========================================================================
# EH_STATE — disambiguating the two meanings of exit 0.
#
# Exit 0 answers both «this host IS the declared one» and «no mandate here»,
# so an absent guard is indistinguishable from a healthy one by exit code
# alone: both are silence. EH_STATE is the out-of-band channel that tells
# them apart WITHOUT changing the exit-code contract every consumer branches
# on. The load-bearing assertion is the first one below.
# ===========================================================================

@test "EH_STATE: on-host and unconfigured BOTH exit 0 but are distinguishable" {
    # The exact conflation that let a machine with no protection read as
    # healthy. Same exit code, different state -- that is the whole fix.
    run bash -c "
      source '$LIB'
      EH_TEST_HOSTNAME='test-host' eh_decision '$BOUND_WS' '$MAP'; on_rc=\$?
      on_state=\$EH_STATE
      eh_decision '$UNBOUND_WS' '$MAP'; un_rc=\$?
      un_state=\$EH_STATE
      printf '%s %s %s %s' \"\$on_rc\" \"\$on_state\" \"\$un_rc\" \"\$un_state\"
    "
    [ "$output" = "0 on-host 0 unconfigured" ]
}

@test "EH_STATE: off-host verdict is labelled off-host" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='some-other-mac' eh_decision '$BOUND_WS' '$MAP'; printf '%s' \"\$EH_STATE\""
    [ "$output" = "off-host" ]
}

@test "EH_STATE: malformed map is labelled fail-closed" {
    run bash -c "source '$LIB'; eh_decision '$BOUND_WS' '$MALFORMED_MAP'; printf '%s' \"\$EH_STATE\""
    [ "$output" = "fail-closed" ]
}

@test "EH_STATE: yq absent degrades to unconfigured, not a false on-host" {
    # Degradation must never masquerade as a passing check.
    run bash -c "
      source '$LIB'
      yq() { return 127; }
      command() { if [ \"\$1\" = -v ] && [ \"\$2\" = yq ]; then return 1; fi; builtin command \"\$@\"; }
      export -f yq command
      EH_TEST_HOSTNAME='test-host' eh_decision '$BOUND_WS' '$MAP'
      printf '%s' \"\$EH_STATE\"
    "
    [ "$output" = "unconfigured" ]
}

@test "EH_STATE: read-only bypass is NOT reported as on-host" {
    # Read-only short-circuits before any host resolution. Calling that
    # 'on-host' would be the same false-health claim in a new place.
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='some-mac' eh_decision_intent '$CANON_WS' '$ABSENT_MAP' readonly; printf '%s' \"\$EH_STATE\""
    [ "$output" = "readonly-bypass" ]
}

@test "EH_STATE: intent resolver labels canon-resolved on-host correctly" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='canon-host' eh_decision_intent '$CANON_WS' '$ABSENT_MAP' mutating; printf '%s' \"\$EH_STATE\""
    [ "$output" = "on-host" ]
}

@test "EH_STATE: intent resolver labels unprovable-host fail-closed" {
    run bash -c "
      source '$LIB'
      yq() { return 127; }
      command() { if [ \"\$1\" = -v ] && [ \"\$2\" = yq ]; then return 1; fi; builtin command \"\$@\"; }
      export -f yq command
      EH_TEST_HOSTNAME='canon-host' eh_decision_intent '$CANON_WS' '$ABSENT_MAP' mutating
      printf '%s' \"\$EH_STATE\"
    "
    [ "$output" = "fail-closed" ]
}

@test "EH_STATE: is set in the CALLER's shell, not a subshell" {
    # If these were subshells the variable would be invisible to the caller
    # and the whole mechanism would silently do nothing.
    run bash -c "source '$LIB'; EH_STATE=unset; EH_TEST_HOSTNAME='test-host' eh_decision '$BOUND_WS' '$MAP'; [ \"\$EH_STATE\" != unset ]"
    [ "$status" -eq 0 ]
}

@test "EH_STATE: is not exported (a stale exported copy would look authoritative)" {
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='test-host' eh_decision '$BOUND_WS' '$MAP'; bash -c 'printf \"%s\" \"\${EH_STATE:-absent}\"'"
    [ "$output" = "absent" ]
}

# ============================================================================
# TUNE-0596 — the library is SOURCED into the caller's shell by the Step-0
# EXECUTION HOST block of every /dr-* command, so it runs under whatever shell
# the agent happens to be (zsh is the macOS default). Every test above runs it
# under `bash -c`, which is exactly why a bashism survived here undetected.
#
# The defect: `IFS=',' read -ra aliases` is bash-only. Under zsh it printed
# "bad option: -a" and — without `set -e` — execution CONTINUED with an empty
# alias list, so eh_host_match returned a perfectly honest-looking 1. A host
# that matched only by ALIAS was therefore reported off-host and told to
# delegate to itself, while the same map under bash resolved on-host.
#
# These cases pin the behaviour under a non-bash shell. They skip (rather than
# fail) where zsh is absent, so a bash-only CI runner stays green while the
# coverage is real on any machine that has zsh.
# ============================================================================

@test "zsh: eh_host_match matches by alias (the TUNE-0596 regression)" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed on this host"
    run zsh -c "source '$LIB'; EH_TEST_HOSTNAME='Test-Host' eh_host_match 'test-host' 'test-host,Test-Host' '100.64.0.42'"
    [ "$status" -eq 0 ]
}

@test "zsh: eh_host_match matches an alias in a later CSV position" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed on this host"
    run zsh -c "source '$LIB'; EH_TEST_HOSTNAME='third' eh_host_match 'req' 'one,two,third' ''"
    [ "$status" -eq 0 ]
}

@test "zsh: eh_host_match still REJECTS a genuine non-match" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed on this host"
    run zsh -c "source '$LIB'; EH_TEST_HOSTNAME='stranger' eh_host_match 'req' 'one,two' ''"
    [ "$status" -eq 1 ]
}

@test "zsh: eh_host_match handles a single alias with no comma" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed on this host"
    run zsh -c "source '$LIB'; EH_TEST_HOSTNAME='solo' eh_host_match 'req' 'solo' ''"
    [ "$status" -eq 0 ]
}

@test "zsh: eh_decision resolves on-host via alias, exactly as bash does" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed on this host"
    run zsh -c "source '$LIB'; EH_TEST_HOSTNAME='Test-Host' eh_decision '$BOUND_WS' '$MAP'"
    [ "$status" -eq 0 ]
    run bash -c "source '$LIB'; EH_TEST_HOSTNAME='Test-Host' eh_decision '$BOUND_WS' '$MAP'"
    [ "$status" -eq 0 ]
}

@test "zsh: eh_decision still reports off-host for a foreign hostname" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed on this host"
    run zsh -c "source '$LIB'; EH_TEST_HOSTNAME='stranger' eh_decision '$BOUND_WS' '$MAP'"
    [ "$status" -eq 10 ]
}

# The alias loop must not depend on shell-specific word splitting. This asserts
# the mechanism directly, so a future rewrite that reintroduces `read -a` or
# `set -- $csv` (zsh does not word-split unquoted expansions by default) fails
# here rather than silently degrading a live routing decision.
@test "eh_host_match: alias parsing uses no bash-only array syntax" {
    # Comments are stripped first: the fix's own commentary NAMES the banned
    # syntax to explain it, and a naive grep matches that prose. Measured — the
    # first version of this test went red on its own explanation.
    run bash -c "sed 's/#.*//' '$LIB' | grep -nE 'read -(r?)a|local -a|declare -a|mapfile|readarray'"
    [ "$status" -ne 0 ]
}

# Positive control for the gate above: the banned syntax IS detected when it is
# real code rather than a comment. Without this, a broken grep would pass
# silently and the gate would be decoration.
@test "eh_host_match: the bash-only-syntax gate can actually fail" {
    probe="$TEST_TMP/probe.sh"
    printf '%s\n' 'f() {' '    local -a arr' '    IFS="," read -ra arr <<< "a,b"' '}' > "$probe"
    run bash -c "sed 's/#.*//' '$probe' | grep -nE 'read -(r?)a|local -a|declare -a|mapfile|readarray'"
    [ "$status" -eq 0 ]
}

# eh_decision must never hand back a verdict its matcher did not produce. Under
# `set -e` a shell incompatibility aborts eh_host_match mid-way; without the
# completion marker the caller reads that abort as a clean on-host/off-host.
# NOTE: the status must be captured with NO command after eh_decision — a
# trailing `echo` overwrites $? and the assertion then reads the echo's 0.
@test "eh_decision: fails closed (3) when the matcher did not complete" {
    run bash -c "source '$LIB'; eh_host_match() { EH_MATCH_COMPLETED=''; return 1; }; EH_TEST_HOSTNAME='stranger' eh_decision '$BOUND_WS' '$MAP'"
    [ "$status" -eq 3 ]
}

# Control for the guard above: the SAME stub that DOES set the marker yields a
# normal verdict, proving the guard keys on the marker and not merely on the
# presence of a stub.
@test "eh_decision: a completed matcher still yields a normal verdict" {
    run bash -c "source '$LIB'; eh_host_match() { EH_MATCH_COMPLETED=1; return 1; }; EH_TEST_HOSTNAME='stranger' eh_decision '$BOUND_WS' '$MAP'"
    [ "$status" -eq 10 ]
}
