#!/usr/bin/env bats
#
# tests/test-docs-migrate.bats — INFRA-0306 Phase 5
#
# Tests for dev-tools/docs-migrate.sh
#
# V-AC-10: --fix produces correct Diátaxis-split; idempotent second run.
# V-AC-11: rollback-safe — on verify-step failure the repo is restored.
#
# Fixture repos are created in $BATS_TEST_TMPDIR (ephemeral, isolated).
# No contact with the real repo.

SCRIPT="${BATS_TEST_DIRNAME}/../dev-tools/docs-migrate.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a minimal git repo with docs/ containing N .md files.
# Usage: _make_git_repo <dir> [extra_basenames...]
_make_git_repo() {
    local dir="$1"; shift
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email "test@test.test"
    git -C "$dir" config user.name "Test"
    mkdir -p "$dir/docs"
    # Always create 3 default stubs
    printf '# getting-started\n' > "$dir/docs/getting-started.md"
    printf '# cli\n'             > "$dir/docs/cli.md"
    printf '# consilium\n'       > "$dir/docs/consilium.md"
    for name in "$@"; do
        printf '# %s\n' "$name" > "$dir/docs/${name}.md"
    done
    git -C "$dir" add .
    git -C "$dir" commit -q -m "initial"
}

# Create a git repo that already has documentation/ but no docs/
_make_migrated_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email "test@test.test"
    git -C "$dir" config user.name "Test"
    mkdir -p "$dir/documentation/tutorials"
    printf '# getting-started\n' > "$dir/documentation/tutorials/getting-started.md"
    git -C "$dir" add .
    git -C "$dir" commit -q -m "migrated"
}

# Create a git repo with BOTH docs/ and documentation/
_make_partial_repo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email "test@test.test"
    git -C "$dir" config user.name "Test"
    mkdir -p "$dir/docs"
    printf '# cli\n' > "$dir/docs/cli.md"
    mkdir -p "$dir/documentation/tutorials"
    printf '# started\n' > "$dir/documentation/tutorials/getting-started.md"
    git -C "$dir" add .
    git -C "$dir" commit -q -m "partial"
}

# ---------------------------------------------------------------------------
# T1: --check on legacy (docs/ present, no documentation/) → exit 1 + "legacy"
# ---------------------------------------------------------------------------
@test "T1: --check legacy layout → exit 1, output contains 'legacy'" {
    local repo="$BATS_TEST_TMPDIR/t1-repo"
    _make_git_repo "$repo"

    run "$SCRIPT" --repo "$repo" --check
    [ "$status" -eq 1 ]
    echo "$output" | grep -qi "legacy"
}

# ---------------------------------------------------------------------------
# T2: --check with both docs/ and documentation/ → exit 2 + "partial"
# ---------------------------------------------------------------------------
@test "T2: --check partial layout (both dirs) → exit 2, output contains 'partial'" {
    local repo="$BATS_TEST_TMPDIR/t2-repo"
    _make_partial_repo "$repo"

    run "$SCRIPT" --repo "$repo" --check
    [ "$status" -eq 2 ]
    echo "$output" | grep -qi "partial"
}

# ---------------------------------------------------------------------------
# T3: --check on already-migrated repo → exit 0 + "migrated"
# ---------------------------------------------------------------------------
@test "T3: --check already-migrated repo → exit 0, output contains 'migrated'" {
    local repo="$BATS_TEST_TMPDIR/t3-repo"
    _make_migrated_repo "$repo"

    run "$SCRIPT" --repo "$repo" --check
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "migrated"
}

# ---------------------------------------------------------------------------
# T4: --fix on legacy repo → Diátaxis split, exit 0 (V-AC-10)
# ---------------------------------------------------------------------------
@test "T4: --fix on legacy repo produces Diátaxis categories, exit 0 (V-AC-10)" {
    local repo="$BATS_TEST_TMPDIR/t4-repo"
    # Create repo with known files from the mapping
    _make_git_repo "$repo" "use-cases" "commands" "evolution" "backlog-workflow"

    DOCS_MIGRATE_BACKUP_DIR="$BATS_TEST_TMPDIR" run "$SCRIPT" --repo "$repo" --fix
    [ "$status" -eq 0 ]

    # docs/ must be gone
    [ ! -d "$repo/docs" ]

    # documentation/ must exist
    [ -d "$repo/documentation" ]

    # Diátaxis categories must exist
    [ -d "$repo/documentation/tutorials" ]
    [ -d "$repo/documentation/reference" ]
    [ -d "$repo/documentation/explanation" ]
    [ -d "$repo/documentation/how-to" ]

    # Known-mapping checks:
    # getting-started → tutorials/
    [ -f "$repo/documentation/tutorials/getting-started.md" ]
    # use-cases → tutorials/
    [ -f "$repo/documentation/tutorials/use-cases.md" ]
    # cli → reference/
    [ -f "$repo/documentation/reference/cli.md" ]
    # commands → reference/
    [ -f "$repo/documentation/reference/commands.md" ]
    # consilium → explanation/
    [ -f "$repo/documentation/explanation/consilium.md" ]
    # evolution → explanation/ (explanation per mapping)
    [ -f "$repo/documentation/explanation/evolution.md" ]
    # backlog-workflow → how-to/
    [ -f "$repo/documentation/how-to/backlog-workflow.md" ]
}

# ---------------------------------------------------------------------------
# T5: second --fix on now-migrated repo → exit 0 no-op (V-AC-10 idempotent)
# ---------------------------------------------------------------------------
@test "T5: second --fix is idempotent no-op, exit 0 (V-AC-10)" {
    local repo="$BATS_TEST_TMPDIR/t5-repo"
    _make_git_repo "$repo"

    DOCS_MIGRATE_BACKUP_DIR="$BATS_TEST_TMPDIR" run "$SCRIPT" --repo "$repo" --fix
    [ "$status" -eq 0 ]

    # Second run
    DOCS_MIGRATE_BACKUP_DIR="$BATS_TEST_TMPDIR" run "$SCRIPT" --repo "$repo" --fix
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "migrated"
}

# ---------------------------------------------------------------------------
# T6: --fix with failing verify step → rollback to pre-fix state, exit 2 (V-AC-11)
# ---------------------------------------------------------------------------
@test "T6: verify-step failure triggers rollback, exit 2, docs/ restored (V-AC-11)" {
    local repo="$BATS_TEST_TMPDIR/t6-repo"
    _make_git_repo "$repo"

    # Plant a check-doc-refs.sh that always fails
    mkdir -p "$repo/scripts"
    cat > "$repo/scripts/check-doc-refs.sh" <<'STUB'
#!/usr/bin/env bash
# stub: always fail to simulate verify-gate failure
exit 1
STUB
    chmod +x "$repo/scripts/check-doc-refs.sh"

    DOCS_MIGRATE_BACKUP_DIR="$BATS_TEST_TMPDIR" run "$SCRIPT" --repo "$repo" --fix
    [ "$status" -eq 2 ]

    # Rollback: docs/ must be restored
    [ -d "$repo/docs" ]
    # documentation/ must be gone (rolled back)
    [ ! -d "$repo/documentation" ]
}

# ---------------------------------------------------------------------------
# T7: unknown-basename file → lands in how-to/ with review-category comment
# ---------------------------------------------------------------------------
@test "T7: unknown-basename file lands in how-to/ with review-category comment" {
    local repo="$BATS_TEST_TMPDIR/t7-repo"
    _make_git_repo "$repo" "some-unknown-topic"

    DOCS_MIGRATE_BACKUP_DIR="$BATS_TEST_TMPDIR" run "$SCRIPT" --repo "$repo" --fix
    [ "$status" -eq 0 ]

    # unknown file must be in how-to/
    [ -f "$repo/documentation/how-to/some-unknown-topic.md" ]
    # review-category comment must be injected
    grep -q "review category" "$repo/documentation/how-to/some-unknown-topic.md"
}

# ---------------------------------------------------------------------------
# T8: path-traversal --repo → exit 4
# ---------------------------------------------------------------------------
@test "T8: path-traversal --repo '../../etc' → exit 4" {
    run "$SCRIPT" --repo "../../etc" --check
    [ "$status" -eq 4 ]
}
