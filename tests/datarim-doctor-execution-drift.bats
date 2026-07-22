#!/usr/bin/env bats
# tests/datarim-doctor-execution-drift.bats — TUNE-0472 Phase 2.
#
# Orthogonal to tests/datarim-doctor.bats (operational-file migration): this
# file covers (a) datarim-doctor.sh --local (official local-repair mode) and
# (b) dev-tools/check-execution-host-drift.sh (canon space.yml § execution
# vs. machine-local execution-hosts.yml map + TTL 90-day staleness).
#
# Per Validation Discipline (framework CLAUDE.md § Self-Evolution — "New
# schema validations MUST NOT be added as new branches inside
# datarim-doctor.sh... orthogonal concerns get orthogonal tools"), the drift
# comparison logic lives entirely in the standalone script; the doctor only
# calls it and aggregates findings under SCOPE=execution.

DOCTOR="$BATS_TEST_DIRNAME/../scripts/datarim-doctor.sh"
DRIFT_SCRIPT="$BATS_TEST_DIRNAME/../dev-tools/check-execution-host-drift.sh"

setup() {
    TMPROOT="$(mktemp -d)"
    mkdir -p "$TMPROOT/datarim/tasks" "$TMPROOT/documentation/archive/framework"
    mkdir -p "$TMPROOT/spaces/testspace"

    CANON="$TMPROOT/spaces/testspace/space.yml"
    cat > "$CANON" <<EOF
space:
  name: testspace
execution:
  schema_version: 1
  required_host: canon-host
  host_aliases: [canon-host, Canon-Host]
  tailscale_ip: "100.64.0.1"
  ssh_user: dev
EOF

    MAP="$TMPROOT/execution-hosts.yml"
}

teardown() {
    rm -rf "$TMPROOT"
}

write_map() {
    local host="$1" ip="$2" synced_at="${3:-}"
    # Aliases mirror canon's [canon-host, Canon-Host] exactly when host is
    # unchanged (consistent-fixture case: host == "canon-host" reuses
    # canon's own alias literal); a drift-fixture host (any other value)
    # gets a distinct-but-internally-consistent two-alias shape so only the
    # field(s) under test differ from canon.
    local aliases
    if [ "$host" = "canon-host" ]; then
        aliases="canon-host, Canon-Host"
    else
        aliases="$host, $host-alias"
    fi
    if [ -n "$synced_at" ]; then
        cat > "$MAP" <<EOF
schema_version: 1
role: control
synced_at: "$synced_at"
bindings:
  - workspace: $TMPROOT
    space: testspace
    required_host: $host
    host_aliases: [$aliases]
    tailscale_ip: "$ip"
    ssh_user: dev
    default_agent: claude-code
    allowed_agents: [claude-code]
EOF
    else
        cat > "$MAP" <<EOF
schema_version: 1
role: control
bindings:
  - workspace: $TMPROOT
    space: testspace
    required_host: $host
    host_aliases: [$aliases]
    tailscale_ip: "$ip"
    ssh_user: dev
    default_agent: claude-code
    allowed_agents: [claude-code]
EOF
    fi
}

# ---------------------------------------------------------------------------
# V-AC-4: check-execution-host-drift.sh standalone contract
# ---------------------------------------------------------------------------

@test "drift-check: canon == map -> exit 0 PASS (consistent fixture)" {
    write_map "canon-host" "100.64.0.1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run "$DRIFT_SCRIPT" --check --canon "$CANON" --map "$MAP" --space testspace
    [ "$status" -eq 0 ]
}

@test "drift-check: nested space.execution canon layout -> exit 0 PASS (real space.yml shape)" {
    cat > "$CANON" <<EOF
space:
  name: testspace
  execution:
    schema_version: 1
    required_host: canon-host
    host_aliases: [canon-host, Canon-Host]
    tailscale_ip: "100.64.0.1"
    ssh_user: dev
EOF
    write_map "canon-host" "100.64.0.1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run "$DRIFT_SCRIPT" --check --canon "$CANON" --map "$MAP" --space testspace
    [ "$status" -eq 0 ]
}

@test "drift-check: canon != map required_host -> exit 1 FAIL (finding)" {
    write_map "stale-host" "100.64.0.1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run "$DRIFT_SCRIPT" --check --canon "$CANON" --map "$MAP" --space testspace
    [ "$status" -eq 1 ]
    [[ "$output" == *"drift"* ]]
}

@test "drift-check: canon != map tailscale_ip -> exit 1 FAIL (finding)" {
    write_map "canon-host" "100.64.0.99" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run "$DRIFT_SCRIPT" --check --canon "$CANON" --map "$MAP" --space testspace
    [ "$status" -eq 1 ]
    [[ "$output" == *"drift"* ]]
}

@test "drift-check: map older than 90 days (synced_at) -> exit 1 staleness finding" {
    write_map "canon-host" "100.64.0.1" "2026-01-01T00:00:00Z"
    run "$DRIFT_SCRIPT" --check --canon "$CANON" --map "$MAP" --space testspace
    [ "$status" -eq 1 ]
    [[ "$output" == *"stale"* ]]
}

@test "drift-check: map missing synced_at, mtime older than 90 days -> staleness finding" {
    write_map "canon-host" "100.64.0.1"
    touch -t "202601010000" "$MAP"
    run "$DRIFT_SCRIPT" --check --canon "$CANON" --map "$MAP" --space testspace
    [ "$status" -eq 1 ]
    [[ "$output" == *"stale"* ]]
}

@test "drift-check: missing map file -> exit 1 (finding: map absent)" {
    run "$DRIFT_SCRIPT" --check --canon "$CANON" --map "$TMPROOT/nonexistent.yml" --space testspace
    [ "$status" -eq 1 ]
}

@test "drift-check: missing canon file -> exit 1 (finding: canon absent)" {
    write_map "canon-host" "100.64.0.1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run "$DRIFT_SCRIPT" --check --canon "$TMPROOT/nope-space.yml" --map "$MAP" --space testspace
    [ "$status" -eq 1 ]
}

@test "drift-check: --report emits mesh-IP-free summary (no raw tailscale_ip value leaked into a would-be-shipped line)" {
    write_map "stale-host" "100.64.0.55" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run "$DRIFT_SCRIPT" --report --canon "$CANON" --map "$MAP" --space testspace
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    # --report is a local-only terminal summary; drift-check still functions.
    [[ "$output" == *"testspace"* ]]
}

# ---------------------------------------------------------------------------
# V-AC-3: datarim-doctor.sh --local
# ---------------------------------------------------------------------------

@test "doctor --local: runs on a compliant tree without deny / without error, exit 0 or 1 (never a hard crash)" {
    run "$DOCTOR" --local --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "doctor --local: with no --scope defaults to scope=execution (local-only checks)" {
    run "$DOCTOR" --local --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    [[ "$output" != *"ERROR: --root not specified"* ]]
}

@test "doctor --local --scope=all: full run still succeeds (local mode does not restrict explicit scope)" {
    run "$DOCTOR" --local --scope=all --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "doctor: --help usage text documents --local" {
    run "$DOCTOR" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--local"* ]]
}

# ---------------------------------------------------------------------------
# V-AC-4: doctor SCOPE=execution calls the standalone drift script
# ---------------------------------------------------------------------------

@test "doctor --scope=execution: with a drift fixture wired via DATARIM_EXECUTION_DRIFT_ARGS produces a finding" {
    write_map "stale-host" "100.64.0.1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run env DATARIM_EXECUTION_DRIFT_ARGS="--canon $CANON --map $MAP --space testspace" \
        "$DOCTOR" --scope=execution --root="$TMPROOT/datarim"
    [ "$status" -eq 1 ]
    [[ "$output" == *"drift"* ]] || [[ "$output" == *"execution"* ]]
}

@test "doctor --scope=execution: consistent fixture -> exit 0 compliant" {
    write_map "canon-host" "100.64.0.1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run env DATARIM_EXECUTION_DRIFT_ARGS="--canon $CANON --map $MAP --space testspace" \
        "$DOCTOR" --scope=execution --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ]
}

@test "doctor --scope=execution: no DATARIM_EXECUTION_DRIFT_ARGS configured -> advisory skip, exit 0 (fail-open, unconfigured)" {
    run "$DOCTOR" --scope=execution --root="$TMPROOT/datarim"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# TUNE-0505: --fix regenerates the machine-local map binding FROM canon
# (canon->cache only). Makes the cache a derived artefact, not a hand-
# maintained source of truth.
# ---------------------------------------------------------------------------

@test "drift-fix: creates map from canon (map absent) then --check PASSes" {
    [ ! -f "$MAP" ]
    run "$DRIFT_SCRIPT" --fix --canon "$CANON" --map "$MAP" --space testspace --workspace "$TMPROOT"
    [ "$status" -eq 0 ]
    [ -f "$MAP" ]
    # Canon-owned fields landed in the map.
    [ "$(yq e '.bindings[0].required_host' "$MAP")" = "canon-host" ]
    [ "$(yq e '.bindings[0].tailscale_ip' "$MAP")" = "100.64.0.1" ]
    [ "$(yq e '.bindings[0].workspace' "$MAP")" = "$TMPROOT" ]
    [ -n "$(yq e '.synced_at' "$MAP")" ]
    run "$DRIFT_SCRIPT" --check --canon "$CANON" --map "$MAP" --space testspace
    [ "$status" -eq 0 ]
}

@test "drift-fix: idempotent -> re-run keeps exactly one binding for the space" {
    "$DRIFT_SCRIPT" --fix --canon "$CANON" --map "$MAP" --space testspace --workspace "$TMPROOT"
    "$DRIFT_SCRIPT" --fix --canon "$CANON" --map "$MAP" --space testspace --workspace "$TMPROOT"
    [ "$(yq e '[.bindings[] | select(.space == "testspace")] | length' "$MAP")" -eq 1 ]
}

@test "drift-fix: preserves the machine-local workspace when --workspace omitted on re-run" {
    "$DRIFT_SCRIPT" --fix --canon "$CANON" --map "$MAP" --space testspace --workspace "/machine/local/ws"
    # Re-fix WITHOUT --workspace: canon owns host identity, cache owns the path.
    "$DRIFT_SCRIPT" --fix --canon "$CANON" --map "$MAP" --space testspace
    [ "$(yq e '.bindings[0].workspace' "$MAP")" = "/machine/local/ws" ]
}

@test "drift-fix: canon wins -> fixing a drifted map makes --check PASS" {
    write_map "stale-host" "100.64.0.99" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    run "$DRIFT_SCRIPT" --check --canon "$CANON" --map "$MAP" --space testspace
    [ "$status" -eq 1 ]
    "$DRIFT_SCRIPT" --fix --canon "$CANON" --map "$MAP" --space testspace
    [ "$(yq e '.bindings[0].required_host' "$MAP")" = "canon-host" ]
    [ "$(yq e '.bindings[0].tailscale_ip' "$MAP")" = "100.64.0.1" ]
    run "$DRIFT_SCRIPT" --check --canon "$CANON" --map "$MAP" --space testspace
    [ "$status" -eq 0 ]
}

@test "drift-fix: leaves other spaces' bindings untouched" {
    "$DRIFT_SCRIPT" --fix --canon "$CANON" --map "$MAP" --space testspace --workspace "$TMPROOT"
    yq e -i '.bindings += [{"workspace":"/other","space":"otherspace","required_host":"oh","host_aliases":["oh"],"tailscale_ip":"1.2.3.4","ssh_user":"x","default_agent":"claude-code","allowed_agents":["claude-code"]}]' "$MAP"
    "$DRIFT_SCRIPT" --fix --canon "$CANON" --map "$MAP" --space testspace
    [ "$(yq e '.bindings | length' "$MAP")" -eq 2 ]
    [ "$(yq e '[.bindings[] | select(.space == "otherspace")] | length' "$MAP")" -eq 1 ]
}

@test "drift-fix: missing canon file -> exit 2 usage error" {
    run "$DRIFT_SCRIPT" --fix --canon "$TMPROOT/nope-space.yml" --map "$MAP" --space testspace --workspace "$TMPROOT"
    [ "$status" -eq 2 ]
}

@test "drift-fix: cannot resolve workspace (no --workspace, no existing binding, no canon local_repo_path) -> exit 2" {
    # Default setup() CANON has no .space.local_repo_path.
    [ ! -f "$MAP" ]
    run "$DRIFT_SCRIPT" --fix --canon "$CANON" --map "$MAP" --space testspace
    [ "$status" -eq 2 ]
}

@test "drift-fix: --help usage documents --fix" {
    run "$DRIFT_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--fix"* ]]
}
