#!/usr/bin/env bats
# tune-0523-archive-sha-gates.bats — verify SHA-chain and prod-merge
# enforcement gates for /dr-archive.
# Usage: bats tests/tune-0523-archive-sha-gates.bats

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SC="$REPO_DIR/dev-tools/check-archive-sha-chain.sh"
PM="$REPO_DIR/dev-tools/check-prod-merge-blocked.sh"

setup() {
    TEST_TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_TMP"
}

# ===========================================================================
# check-archive-sha-chain.sh
# ===========================================================================

@test "S1: check-archive-sha-chain exists and is executable" {
    [ -f "$SC" ]
    [ -x "$SC" ]
}

@test "S1: missing required args → exit 2" {
    run bash "$SC" --task-description "$TEST_TMP/nope.md"
    [ "$status" -eq 2 ]
}

@test "S1: missing task description file → exit 0 (no probe required)" {
    run bash "$SC" --task-description "$TEST_TMP/nope.md" --archive-doc "$TEST_TMP/nope.md"
    [ "$status" -eq 0 ]
}

@test "S1: task without requires_runtime_probe → exit 0 (skip)" {
    cat > "$TEST_TMP/task.md" <<'EOF'
---
title: no probe
---
EOF
    run bash "$SC" --task-description "$TEST_TMP/task.md" --archive-doc "$TEST_TMP/nope.md"
    [ "$status" -eq 0 ]
}

@test "S1: requires_runtime_probe: true, no archive doc → exit 1" {
    cat > "$TEST_TMP/task.md" <<'EOF'
---
title: prod task
requires_runtime_probe: true
---
EOF
    run bash "$SC" --task-description "$TEST_TMP/task.md" --archive-doc "$TEST_TMP/nope.md"
    [ "$status" -eq 1 ]
}

@test "S1: SHA-chain evidence present (2+ markers) → exit 0" {
    cat > "$TEST_TMP/task.md" <<'EOF'
---
title: prod task
requires_runtime_probe: true
---
EOF
    cat > "$TEST_TMP/archive.md" <<'EOF'
## Verification
SHA chain verified: LOCAL_HEAD = abcdef0123456789abcdef0123456789abcdef01
ORIGIN_HEAD = abcdef0123456789abcdef0123456789abcdef01
PROD running image: abcdef0123456789abcdef0123456789abcdef01
local == origin == PROD: PASS
EOF
    run bash "$SC" --task-description "$TEST_TMP/task.md" --archive-doc "$TEST_TMP/archive.md"
    [ "$status" -eq 0 ]
}

@test "S1: SHA-chain evidence absent → exit 1" {
    cat > "$TEST_TMP/task.md" <<'EOF'
---
title: prod task
requires_runtime_probe: true
---
EOF
    cat > "$TEST_TMP/archive.md" <<'EOF'
## Archive
Task completed. No verification.
EOF
    run bash "$SC" --task-description "$TEST_TMP/task.md" --archive-doc "$TEST_TMP/archive.md"
    [ "$status" -eq 1 ]
}

@test "S1: BLOCKED with operator confirmation → exit 0 (valid exception)" {
    cat > "$TEST_TMP/task.md" <<'EOF'
---
title: prod task
requires_runtime_probe: true
---
EOF
    cat > "$TEST_TMP/archive.md" <<'EOF'
## Verification
Production was unreachable (BLOCKED). Operator confirmed out-of-band verification:
deployment was verified manually on the host. Operator approved archiving.
EOF
    run bash "$SC" --task-description "$TEST_TMP/task.md" --archive-doc "$TEST_TMP/archive.md"
    [ "$status" -eq 0 ]
}

# ===========================================================================
# check-prod-merge-blocked.sh
# ===========================================================================

@test "P1: check-prod-merge-blocked exists and is executable" {
    [ -f "$PM" ]
    [ -x "$PM" ]
}

@test "P1: non-deploy task → exit 0 (skip)" {
    cat > "$TEST_TMP/task.md" <<'EOF'
---
title: docs update
---
EOF
    run bash "$PM" --task-description "$TEST_TMP/task.md" --archive-doc "$TEST_TMP/nope.md"
    [ "$status" -eq 0 ]
}

@test "P1: deploy-class task, no archive → exit 1" {
    cat > "$TEST_TMP/task.md" <<'EOF'
---
title: deploy nginx config
---
This task touches production deploy and nginx configuration.
EOF
    run bash "$PM" --task-description "$TEST_TMP/task.md" --archive-doc "$TEST_TMP/nope.md"
    [ "$status" -eq 1 ]
}

@test "P1: deploy-class task, prod-merge verified → exit 0" {
    cat > "$TEST_TMP/task.md" <<'EOF'
---
title: production deploy
---
Deploy to production server with docker compose.
EOF
    cat > "$TEST_TMP/archive.md" <<'EOF'
## Verification
Prod merge verified. Post-deploy health probe passed.
Running version: v2.59.0 confirmed on production.
systemctl status active, readiness probe PASS.
EOF
    run bash "$PM" --task-description "$TEST_TMP/task.md" --archive-doc "$TEST_TMP/archive.md"
    [ "$status" -eq 0 ]
}

@test "P1: deploy-class task, BLOCKED with operator confirmation → exit 0" {
    cat > "$TEST_TMP/task.md" <<'EOF'
---
title: production deploy
---
Deploy to production.
EOF
    cat > "$TEST_TMP/archive.md" <<'EOF'
## Verification
Production unreachable (BLOCKED). Operator confirmed out-of-band verification.
Deployment was verified manually. Operator approved.
EOF
    run bash "$PM" --task-description "$TEST_TMP/task.md" --archive-doc "$TEST_TMP/archive.md"
    [ "$status" -eq 0 ]
}

@test "P1: deploy-class task, BLOCKED without operator → exit 1" {
    cat > "$TEST_TMP/task.md" <<'EOF'
---
title: production deploy
---
Deploy to production.
EOF
    cat > "$TEST_TMP/archive.md" <<'EOF'
## Verification
Production unreachable (BLOCKED). Could not verify.
EOF
    run bash "$PM" --task-description "$TEST_TMP/task.md" --archive-doc "$TEST_TMP/archive.md"
    [ "$status" -eq 1 ]
}

# ===========================================================================
# Wiring: dr-archive.md references the gates
# ===========================================================================

@test "W1: dr-archive.md references check-archive-sha-chain.sh" {
    run grep -c "check-archive-sha-chain" "$REPO_DIR/commands/dr-archive.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "W2: dr-archive.md references check-prod-merge-blocked.sh" {
    run grep -c "check-prod-merge-blocked" "$REPO_DIR/commands/dr-archive.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}
