#!/usr/bin/env bats
#
# bats spec for dev-tools/check-inventory-runtime-drift.sh — declarative
# inventory vs runtime drift auditor (TUNE-0124). Fully offline: the SSH
# transport is replaced by an injectable --probe-cmd fixture that echoes
# canned runtime facts from a lookup table, so no real host is contacted.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../check-inventory-runtime-drift.sh"
    WORK="$(mktemp -d)"

    # Fixture probe: reads runtime facts from $WORK/runtime.tsv
    #   <host>\t<fact>\t<value>
    # An absent (host,fact) row yields empty output (unreachable/unknown).
    PROBE="$WORK/probe.sh"
    cat >"$PROBE" <<'EOF'
#!/usr/bin/env bash
host="$1"; fact="$2"
awk -F'\t' -v h="$host" -v f="$fact" '$1==h && $2==f {print $3; exit}' "$RUNTIME_TSV" 2>/dev/null
EOF
    chmod +x "$PROBE"
    export RUNTIME_TSV="$WORK/runtime.tsv"
    : >"$RUNTIME_TSV"
}

teardown() {
    rm -rf "$WORK"
}

write_inventory() {
    cat >"$WORK/inventory.md"
}

runtime_row() {
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$RUNTIME_TSV"
}

# ---------------------------------------------------------------------------
# 1. no drift — every declared fact matches runtime → exit 0
# ---------------------------------------------------------------------------
@test "no-drift — all declared facts match runtime exits 0" {
    write_inventory <<'EOF'
host: alpha
public_ip: 203.0.113.10
tailscale_ip: 100.64.0.10
firewall: active
EOF
    runtime_row alpha public_ip 203.0.113.10
    runtime_row alpha tailscale_ip 100.64.0.10
    runtime_row alpha firewall active

    run "$SCRIPT" --inventory "$WORK/inventory.md" --probe-cmd "$PROBE"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 2. public-IP drift — the INFRA-0065 scenario: declared IP no longer live
# ---------------------------------------------------------------------------
@test "public-ip-drift — declared public IP differs from runtime exits 1" {
    write_inventory <<'EOF'
host: beta
public_ip: 203.0.113.20
EOF
    runtime_row beta public_ip 198.51.100.99

    run "$SCRIPT" --inventory "$WORK/inventory.md" --probe-cmd "$PROBE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"DRIFT beta public_ip declared=203.0.113.20 runtime=198.51.100.99"* ]]
}

# ---------------------------------------------------------------------------
# 3. tailscale drift
# ---------------------------------------------------------------------------
@test "tailscale-drift — declared mesh IP differs from runtime exits 1" {
    write_inventory <<'EOF'
host: gamma
tailscale_ip: 100.64.0.30
EOF
    runtime_row gamma tailscale_ip 100.64.0.31

    run "$SCRIPT" --inventory "$WORK/inventory.md" --probe-cmd "$PROBE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"DRIFT gamma tailscale_ip"* ]]
}

# ---------------------------------------------------------------------------
# 4. firewall-posture drift
# ---------------------------------------------------------------------------
@test "firewall-drift — declared inactive but runtime active exits 1" {
    write_inventory <<'EOF'
host: delta
firewall: inactive
EOF
    runtime_row delta firewall active

    run "$SCRIPT" --inventory "$WORK/inventory.md" --probe-cmd "$PROBE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"DRIFT delta firewall declared=inactive runtime=active"* ]]
}

# ---------------------------------------------------------------------------
# 5. unreachable host — empty runtime is NOT drift (exit 0)
# ---------------------------------------------------------------------------
@test "unreachable — empty runtime value is not counted as drift exits 0" {
    write_inventory <<'EOF'
host: epsilon
public_ip: 203.0.113.50
EOF
    # no runtime row for epsilon → probe returns empty
    run "$SCRIPT" --inventory "$WORK/inventory.md" --probe-cmd "$PROBE"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 6. multiple hosts, mixed — one clean, one drifting → exit 1
# ---------------------------------------------------------------------------
@test "multi-host — one drift among many exits 1 with single DRIFT line" {
    write_inventory <<'EOF'
host: h1
public_ip: 203.0.113.1
---
host: h2
public_ip: 203.0.113.2
EOF
    runtime_row h1 public_ip 203.0.113.1
    runtime_row h2 public_ip 203.0.113.222

    run "$SCRIPT" --inventory "$WORK/inventory.md" --probe-cmd "$PROBE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"DRIFT h2 public_ip"* ]]
    [[ "$output" != *"DRIFT h1"* ]]
}

# ---------------------------------------------------------------------------
# 7. --host restricts scope
# ---------------------------------------------------------------------------
@test "host-filter — --host limits audit to the named host" {
    write_inventory <<'EOF'
host: keep
public_ip: 203.0.113.1
---
host: skip
public_ip: 203.0.113.2
EOF
    runtime_row keep public_ip 203.0.113.1
    runtime_row skip public_ip 203.0.113.999   # would drift, but out of scope

    run "$SCRIPT" --inventory "$WORK/inventory.md" --probe-cmd "$PROBE" --host keep
    [ "$status" -eq 0 ]
    [[ "$output" != *"skip"* ]]
}

# ---------------------------------------------------------------------------
# 8. markdown-decorated keys tolerated ("- host:", "| public_ip:")
# ---------------------------------------------------------------------------
@test "markdown-decoration — list/table-decorated keys parse correctly" {
    write_inventory <<'EOF'
Some prose about the fleet.

- host: deco
- public_ip: 203.0.113.7
EOF
    runtime_row deco public_ip 203.0.113.7
    run "$SCRIPT" --inventory "$WORK/inventory.md" --probe-cmd "$PROBE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK deco public_ip"* ]]
}

# ---------------------------------------------------------------------------
# 9. json format
# ---------------------------------------------------------------------------
@test "json-format — drift emitted as one JSON object per line" {
    write_inventory <<'EOF'
host: jhost
public_ip: 203.0.113.1
EOF
    runtime_row jhost public_ip 203.0.113.9
    run "$SCRIPT" --inventory "$WORK/inventory.md" --probe-cmd "$PROBE" --format json
    [ "$status" -eq 1 ]
    [[ "$output" == *'"status":"DRIFT"'* ]]
    [[ "$output" == *'"host":"jhost"'* ]]
    [[ "$output" == *'"runtime":"203.0.113.9"'* ]]
}

# ---------------------------------------------------------------------------
# 10. --quiet suppresses OK lines but keeps DRIFT
# ---------------------------------------------------------------------------
@test "quiet — OK lines suppressed, DRIFT lines retained" {
    write_inventory <<'EOF'
host: q1
public_ip: 203.0.113.1
---
host: q2
public_ip: 203.0.113.2
EOF
    runtime_row q1 public_ip 203.0.113.1        # OK
    runtime_row q2 public_ip 203.0.113.222      # DRIFT

    run "$SCRIPT" --inventory "$WORK/inventory.md" --probe-cmd "$PROBE" --quiet
    [ "$status" -eq 1 ]
    [[ "$output" != *"OK q1"* ]]
    [[ "$output" == *"DRIFT q2"* ]]
}

# ---------------------------------------------------------------------------
# 11. usage — missing --inventory exits 2
# ---------------------------------------------------------------------------
@test "usage — missing --inventory exits 2" {
    run "$SCRIPT" --probe-cmd "$PROBE"
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# 12. usage — unreadable inventory exits 2
# ---------------------------------------------------------------------------
@test "usage — unreadable inventory file exits 2" {
    run "$SCRIPT" --inventory "$WORK/does-not-exist.md" --probe-cmd "$PROBE"
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# 13. usage — unknown argument exits 2
# ---------------------------------------------------------------------------
@test "usage — unknown argument exits 2" {
    run "$SCRIPT" --inventory "$WORK/inventory.md" --bogus
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# 14. --help / --version exit 0
# ---------------------------------------------------------------------------
@test "help — --help exits 0 and prints usage" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "version — --version exits 0" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"check-inventory-runtime-drift.sh"* ]]
}
