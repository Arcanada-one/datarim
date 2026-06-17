#!/usr/bin/env bats
#
# bats spec for dev-tools/check-db-relocation-class.sh — DB relocation/
# decommission task classifier. Mirrors check-deploy-class.bats idiom.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../check-db-relocation-class.sh"
    WORK="$(mktemp -d)"
}

teardown() {
    rm -rf "$WORK"
}

# ---------------------------------------------------------------------------
# 1. classifier-arm-type-field — frontmatter type: db-relocation
# ---------------------------------------------------------------------------
@test "classifier-arm-type-field — type:db-relocation exits 0" {
    cat >"$WORK/task.md" <<'EOF'
---
type: db-relocation
title: Move DB to new host
---

Move the database from old host to new host.
EOF
    run "$SCRIPT" --task-description "$WORK/task.md"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 2. classifier-arm-type-decommission — frontmatter type: db-decommission
# ---------------------------------------------------------------------------
@test "classifier-arm-type-decommission — type:db-decommission exits 0" {
    cat >"$WORK/task.md" <<'EOF'
---
type: db-decommission
title: Decommission old DB server
---

Decommission the old database server after migration.
EOF
    run "$SCRIPT" --task-description "$WORK/task.md"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 3. classifier-arm-keyword-plus-dbhost — body: relocate + DB_HOST
# ---------------------------------------------------------------------------
@test "classifier-arm-keyword-plus-dbhost — relocate + DB_HOST exits 0" {
    cat >"$WORK/task.md" <<'EOF'
---
title: Database migration
---

Relocate the database from the old host.
The application currently points DB_HOST=23.88.34.218 via environment variable.
After migration update the connection string to the new host.
EOF
    run "$SCRIPT" --task-description "$WORK/task.md"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 4. classifier-skip-keyword-only — body has 'relocate' but no DB-host signal
# ---------------------------------------------------------------------------
@test "classifier-skip-keyword-only — relocate without DB signal exits 1" {
    cat >"$WORK/task.md" <<'EOF'
---
title: File relocation
---

Relocate static assets to the new CDN endpoint.
No database changes involved.
EOF
    run "$SCRIPT" --task-description "$WORK/task.md"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# 5. classifier-skip-unrelated — plain content task
# ---------------------------------------------------------------------------
@test "classifier-skip-unrelated — content task exits 1" {
    cat >"$WORK/task.md" <<'EOF'
---
type: content
title: Write blog post
---

Write a blog post about the product launch.
No infrastructure changes.
EOF
    run "$SCRIPT" --task-description "$WORK/task.md"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# 6. classifier-usage-missing-td — no --task-description provided
# ---------------------------------------------------------------------------
@test "classifier-usage-missing-td — missing flag exits 2" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# 7. classifier-usage-file-absent — path does not exist
# ---------------------------------------------------------------------------
@test "classifier-usage-file-absent — missing file exits 2" {
    run "$SCRIPT" --task-description /no/such/path/task.md
    [ "$status" -eq 2 ]
}
