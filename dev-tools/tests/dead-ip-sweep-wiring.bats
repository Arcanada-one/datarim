#!/usr/bin/env bats
#
# bats spec for wiring: check-db-relocation-class.sh + dead-ip-consumer-sweep.sh
# together. Covers: relocation task + live consumer blocks, clean tree passes,
# non-relocation task skips via classifier exit 1.

setup() {
    SWEEP="${BATS_TEST_DIRNAME}/../dead-ip-consumer-sweep.sh"
    CLASSIFIER="${BATS_TEST_DIRNAME}/../check-db-relocation-class.sh"
    WORK="$(mktemp -d)"
}

teardown() {
    rm -rf "$WORK"
}

# ---------------------------------------------------------------------------
# 1. Relocation-class task + planted live consumer → chain blocks (exit 1)
# ---------------------------------------------------------------------------
@test "wiring: relocation-class + live consumer exits 1" {
    # Task description: relocation-class
    cat >"$WORK/task.md" <<'EOF'
---
type: db-relocation
title: Migrate DB to new host
decommissioned_ip: 23.88.34.218
---

Relocate DB from 23.88.34.218 to new host.
DB_HOST=23.88.34.218 currently in environment.
EOF

    # Live consumer in the workspace
    mkdir -p "$WORK/Projects/App/code"
    cat >"$WORK/Projects/App/code/.env" <<'EOF'
DB_HOST=23.88.34.218
DB_PORT=5432
EOF

    # Valid audit (but live hit should still block)
    cat >"$WORK/audit.md" <<'EOF'
dead_ip: 23.88.34.218
live_consumers: 0
assertion: zero live consumers confirmed
EOF

    # 1. Classifier must arm
    run "$CLASSIFIER" --task-description "$WORK/task.md"
    [ "$status" -eq 0 ]

    # 2. Sweep must block due to live consumer
    run "$SWEEP" --dead-ip 23.88.34.218 --workspace-root "$WORK" --audit "$WORK/audit.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK"* ]]
}

# ---------------------------------------------------------------------------
# 2. Relocation-class task + clean tree + asserting audit → chain passes
# ---------------------------------------------------------------------------
@test "wiring: relocation-class + clean tree + audit exits 0" {
    cat >"$WORK/task.md" <<'EOF'
---
type: db-relocation
title: Migrate DB to new host
decommissioned_ip: 23.88.34.218
---

Relocate DB from 23.88.34.218 to new host.
EOF

    # No live consumer — all configs reference new IP
    mkdir -p "$WORK/Projects/App/code"
    cat >"$WORK/Projects/App/code/.env" <<'EOF'
DB_HOST=10.0.0.5
DB_PORT=5432
EOF

    # Valid audit
    cat >"$WORK/audit.md" <<'EOF'
dead_ip: 23.88.34.218
live_consumers: 0
assertion: zero live consumers confirmed
EOF

    # 1. Classifier must arm
    run "$CLASSIFIER" --task-description "$WORK/task.md"
    [ "$status" -eq 0 ]

    # 2. Sweep must pass
    run "$SWEEP" --dead-ip 23.88.34.218 --workspace-root "$WORK" --audit "$WORK/audit.md"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 3. Non-relocation task → classifier exit 1 → gate should be skipped
# ---------------------------------------------------------------------------
@test "wiring: non-relocation task — classifier skips (exit 1)" {
    cat >"$WORK/task.md" <<'EOF'
---
type: feature
title: Add authentication
---

Implement OAuth2 authentication for the web app.
No database migration or relocation involved.
EOF

    # Classifier must NOT arm (exit 1 = skip)
    run "$CLASSIFIER" --task-description "$WORK/task.md"
    [ "$status" -eq 1 ]
    # Sweep is not invoked when classifier exits 1
}
