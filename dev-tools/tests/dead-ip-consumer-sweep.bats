#!/usr/bin/env bats
#
# bats spec for dev-tools/dead-ip-consumer-sweep.sh — fail-closed dead-IP
# sweep verifier. Covers: pass (clean tree), block (live class-a/b hit),
# skip (historical/commented), usage errors, audit-absent, defensive invariant.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../dead-ip-consumer-sweep.sh"
    WORK="$(mktemp -d)"
}

teardown() {
    rm -rf "$WORK"
}

# ---------------------------------------------------------------------------
# 1. clean-pass — no reference to dead IP anywhere
# ---------------------------------------------------------------------------
@test "clean-pass — no dead-IP reference exits 0" {
    mkdir -p "$WORK/spaces/db/code" "$WORK/Projects/App/code"
    cat >"$WORK/spaces/db/space.yml" <<'EOF'
name: db
servers:
  - ip: 10.0.0.5
EOF
    cat >"$WORK/Projects/App/code/config.yml" <<'EOF'
db_host: 10.0.0.5
EOF
    # Create required audit asserting zero live consumers
    cat >"$WORK/audit.md" <<EOF
# Audit
dead_ip: 23.88.34.218
live_consumers: 0
assertion: zero live consumers confirmed
EOF
    run "$SCRIPT" --dead-ip 23.88.34.218 --workspace-root "$WORK" --audit "$WORK/audit.md"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 2. block-on-a-live-connstring — class-a: live connection string in config
# ---------------------------------------------------------------------------
@test "block-on-a-live-connstring — class-a hit exits 1" {
    mkdir -p "$WORK/Projects/App/code"
    cat >"$WORK/Projects/App/code/.env" <<'EOF'
DB_HOST=23.88.34.218
DB_PORT=5432
EOF
    cat >"$WORK/audit.md" <<'EOF'
# Audit
dead_ip: 23.88.34.218
live_consumers: 0
assertion: zero live consumers confirmed
EOF
    run "$SCRIPT" --dead-ip 23.88.34.218 --workspace-root "$WORK" --audit "$WORK/audit.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
}

# ---------------------------------------------------------------------------
# 3. block-on-b-live-bind — class-b: bind/listen directive on dead IP
# ---------------------------------------------------------------------------
@test "block-on-b-live-bind — class-b hit exits 1" {
    mkdir -p "$WORK/Projects/Svc/code"
    cat >"$WORK/Projects/Svc/code/redis.conf" <<'EOF'
bind 23.88.34.218
port 6379
EOF
    cat >"$WORK/audit.md" <<'EOF'
# Audit
dead_ip: 23.88.34.218
live_consumers: 0
assertion: zero live consumers confirmed
EOF
    run "$SCRIPT" --dead-ip 23.88.34.218 --workspace-root "$WORK" --audit "$WORK/audit.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
}

# ---------------------------------------------------------------------------
# 4. c-historical-not-blocked — historical/commented references do not block
# ---------------------------------------------------------------------------
@test "c-historical-not-blocked — commented/archive reference exits 0" {
    mkdir -p "$WORK/documentation/archive"
    cat >"$WORK/documentation/archive/old-infra.md" <<'EOF'
# Old infra (decommissioned)
Previously hosted at 23.88.34.218 (now offline, migrated 2026-06-10).
EOF
    mkdir -p "$WORK/Projects/App/code"
    cat >"$WORK/Projects/App/code/config.yml" <<'EOF'
# Old DB was at 23.88.34.218, now using 10.0.0.5
db_host: 10.0.0.5
EOF
    cat >"$WORK/audit.md" <<'EOF'
# Audit
dead_ip: 23.88.34.218
live_consumers: 0
assertion: zero live consumers confirmed
EOF
    run "$SCRIPT" --dead-ip 23.88.34.218 --workspace-root "$WORK" --audit "$WORK/audit.md"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 5. usage-exit-2-missing-dead-ip — no --dead-ip supplied
# ---------------------------------------------------------------------------
@test "usage-exit-2-missing-dead-ip — missing flag exits 2" {
    run "$SCRIPT" --workspace-root "$WORK"
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# 6. usage-exit-2-bad-ip — invalid IP string
# ---------------------------------------------------------------------------
@test "usage-exit-2-bad-ip — invalid IP exits 2" {
    run "$SCRIPT" --dead-ip not.an.ip --workspace-root "$WORK"
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# 7. fail-closed-unreadable-root — workspace root does not exist
# ---------------------------------------------------------------------------
@test "fail-closed-unreadable-root — missing root exits non-zero" {
    run "$SCRIPT" --dead-ip 23.88.34.218 --workspace-root /no/such/dir/xyz
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# 8. audit-absent-block — clean tree but required --audit file is missing
# ---------------------------------------------------------------------------
@test "audit-absent-block — no audit file exits 1" {
    mkdir -p "$WORK/Projects/App/code"
    cat >"$WORK/Projects/App/code/config.yml" <<'EOF'
db_host: 10.0.0.5
EOF
    run "$SCRIPT" --dead-ip 23.88.34.218 --workspace-root "$WORK" --audit "$WORK/nonexistent-audit.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
}

# ---------------------------------------------------------------------------
# 9. audit-present-clean-pass — clean tree + asserting audit present
# ---------------------------------------------------------------------------
@test "audit-present-clean-pass — clean tree with valid audit exits 0" {
    mkdir -p "$WORK/Projects/App/code"
    cat >"$WORK/Projects/App/code/config.yml" <<'EOF'
db_host: 10.0.0.5
EOF
    cat >"$WORK/audit.md" <<'EOF'
# Dead-IP Audit
dead_ip: 23.88.34.218
live_consumers: 0
assertion: zero live consumers confirmed
EOF
    run "$SCRIPT" --dead-ip 23.88.34.218 --workspace-root "$WORK" --audit "$WORK/audit.md"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 10. audit-not-asserting-block — audit exists but no zero-live-consumer assertion
# ---------------------------------------------------------------------------
@test "audit-not-asserting-block — audit without assertion exits 1" {
    mkdir -p "$WORK/Projects/App/code"
    cat >"$WORK/Projects/App/code/config.yml" <<'EOF'
db_host: 10.0.0.5
EOF
    cat >"$WORK/audit.md" <<'EOF'
# Dead-IP Audit
dead_ip: 23.88.34.218
some_note: investigated
EOF
    run "$SCRIPT" --dead-ip 23.88.34.218 --workspace-root "$WORK" --audit "$WORK/audit.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
}

# ---------------------------------------------------------------------------
# 11. defensive-invariant — BLOCK path produces BLOCK wording
# ---------------------------------------------------------------------------
@test "defensive-invariant — live hit wording matches non-zero exit" {
    mkdir -p "$WORK/Projects/App/code"
    cat >"$WORK/Projects/App/code/.env" <<'EOF'
DB_HOST=23.88.34.218
EOF
    cat >"$WORK/audit.md" <<'EOF'
dead_ip: 23.88.34.218
live_consumers: 0
assertion: zero live consumers confirmed
EOF
    run "$SCRIPT" --dead-ip 23.88.34.218 --workspace-root "$WORK" --audit "$WORK/audit.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
}

# ---------------------------------------------------------------------------
# 12. d-cross-project-unresolved-block — IP in spaces/ yml, no accept marker
# ---------------------------------------------------------------------------
@test "d-cross-project-unresolved-block — space.yml live reference exits 1" {
    mkdir -p "$WORK/spaces/foreign"
    cat >"$WORK/spaces/foreign/space.yml" <<'EOF'
name: foreign
servers:
  - ip: 23.88.34.218
    role: db
EOF
    cat >"$WORK/audit.md" <<'EOF'
dead_ip: 23.88.34.218
live_consumers: 0
assertion: zero live consumers confirmed
EOF
    run "$SCRIPT" --dead-ip 23.88.34.218 --workspace-root "$WORK" --audit "$WORK/audit.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
}

# ---------------------------------------------------------------------------
# 13. d-bare-ip-in-list-block — bare keyless IP list item in space.yml blocked
# ---------------------------------------------------------------------------
@test "d-bare-ip-in-list-block — bare IP list item in space.yml exits 1" {
    mkdir -p "$WORK/spaces/cluster"
    cat >"$WORK/spaces/cluster/space.yml" <<'EOF'
name: cluster
cluster_hosts:
  - 23.88.34.218
  - 10.0.0.2
EOF
    cat >"$WORK/audit.md" <<'EOF'
dead_ip: 23.88.34.218
live_consumers: 0
assertion: zero live consumers confirmed
EOF
    run "$SCRIPT" --dead-ip 23.88.34.218 --workspace-root "$WORK" --audit "$WORK/audit.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
}
