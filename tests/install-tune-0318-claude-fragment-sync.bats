#!/usr/bin/env bats
# tests/install-tune-0318-claude-fragment-sync.bats
#
# `install.sh --with-claude` syncs templates/coworker-delegation-fragment.md
# into $CLAUDE_DIR/CLAUDE.md § Coworker Delegation via sentinel-based block
# replace (CLAUDE_FRAGMENT_BEGIN/END). Contract:
#   - injects/updates only the sentinel-delimited block; surrounding
#     operator content is preserved byte-exact
#   - idempotent: unchanged fragment + re-run = no mutation
#   - fragment-content-change triggers re-sync
#   - fail-soft: missing sentinels -> recipe printed, file untouched
#   - fail-soft: missing CLAUDE.md -> skipped, no file created
#   - --dry-run never touches CLAUDE.md

load 'helpers/install_fixture'

setup() {
    setup_fixture
    mkdir -p "$FAKE_REPO/templates"
    printf 'FRAGMENT-CONTENT-V1\nsecond line\n' > "$FAKE_REPO/templates/coworker-delegation-fragment.md"
}

seed_claude_md_with_sentinels() {
    mkdir -p "$FAKE_CLAUDE"
    cat > "$FAKE_CLAUDE/CLAUDE.md" <<'EOF'
# My personal file

## Coworker Delegation
<!-- coworker-fragment:begin -->
<!-- coworker-fragment:end -->

## Other section
unrelated operator content
EOF
}

@test "T1: --with-claude injects fragment between sentinels, preserves surrounding content" {
    seed_claude_md_with_sentinels
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 0 ]
    run grep -F "FRAGMENT-CONTENT-V1" "$FAKE_CLAUDE/CLAUDE.md"
    [ "$status" -eq 0 ]
    run grep -F "# My personal file" "$FAKE_CLAUDE/CLAUDE.md"
    [ "$status" -eq 0 ]
    run grep -F "## Other section" "$FAKE_CLAUDE/CLAUDE.md"
    [ "$status" -eq 0 ]
    run grep -F "unrelated operator content" "$FAKE_CLAUDE/CLAUDE.md"
    [ "$status" -eq 0 ]
}

@test "T2: re-run with unchanged fragment is idempotent (byte-identical, single sentinel pair)" {
    seed_claude_md_with_sentinels
    env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh" --with-claude >/dev/null
    local sum1
    sum1=$(md5sum "$FAKE_CLAUDE/CLAUDE.md" | awk '{print $1}')

    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 0 ]
    [[ "$output" == *"already up to date"* ]]

    local sum2
    sum2=$(md5sum "$FAKE_CLAUDE/CLAUDE.md" | awk '{print $1}')
    [ "$sum1" = "$sum2" ]

    run grep -cF "<!-- coworker-fragment:begin -->" "$FAKE_CLAUDE/CLAUDE.md"
    [ "$output" -eq 1 ]
    run grep -cF "<!-- coworker-fragment:end -->" "$FAKE_CLAUDE/CLAUDE.md"
    [ "$output" -eq 1 ]
}

@test "T3: fragment-content-change re-syncs the block on next run" {
    seed_claude_md_with_sentinels
    env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh" --with-claude >/dev/null
    run grep -F "FRAGMENT-CONTENT-V1" "$FAKE_CLAUDE/CLAUDE.md"
    [ "$status" -eq 0 ]

    printf 'FRAGMENT-CONTENT-V2\n' > "$FAKE_REPO/templates/coworker-delegation-fragment.md"
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 0 ]
    [[ "$output" == *"updated from"* ]]

    run grep -F "FRAGMENT-CONTENT-V2" "$FAKE_CLAUDE/CLAUDE.md"
    [ "$status" -eq 0 ]
    run grep -F "FRAGMENT-CONTENT-V1" "$FAKE_CLAUDE/CLAUDE.md"
    [ "$status" -eq 1 ]
    # Surrounding content still intact after re-sync.
    run grep -F "unrelated operator content" "$FAKE_CLAUDE/CLAUDE.md"
    [ "$status" -eq 0 ]
}

@test "T4: missing sentinels -> file untouched, recipe printed to stderr" {
    mkdir -p "$FAKE_CLAUDE"
    cat > "$FAKE_CLAUDE/CLAUDE.md" <<'EOF'
# My personal file, no sentinels here.
EOF
    local sum1
    sum1=$(md5sum "$FAKE_CLAUDE/CLAUDE.md" | awk '{print $1}')

    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 0 ]
    [[ "$output" == *"NOTE:"* ]]
    [[ "$output" == *"coworker-fragment:begin"* ]]

    local sum2
    sum2=$(md5sum "$FAKE_CLAUDE/CLAUDE.md" | awk '{print $1}')
    [ "$sum1" = "$sum2" ]
}

@test "T5: missing CLAUDE.md -> skipped, no file created" {
    [ ! -f "$FAKE_CLAUDE/CLAUDE.md" ]
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP:"* ]]
    [ ! -f "$FAKE_CLAUDE/CLAUDE.md" ]
}

@test "T6: --dry-run never touches CLAUDE.md" {
    seed_claude_md_with_sentinels
    local sum1
    sum1=$(md5sum "$FAKE_CLAUDE/CLAUDE.md" | awk '{print $1}')

    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh" --with-claude --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY: sync coworker-delegation fragment"* ]]

    local sum2
    sum2=$(md5sum "$FAKE_CLAUDE/CLAUDE.md" | awk '{print $1}')
    [ "$sum1" = "$sum2" ]
}

@test "T7: missing fragment source -> no-op, no error (repo-only feature, not shipped to every consumer)" {
    rm -f "$FAKE_REPO/templates/coworker-delegation-fragment.md"
    seed_claude_md_with_sentinels
    local sum1
    sum1=$(md5sum "$FAKE_CLAUDE/CLAUDE.md" | awk '{print $1}')

    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 0 ]

    local sum2
    sum2=$(md5sum "$FAKE_CLAUDE/CLAUDE.md" | awk '{print $1}')
    [ "$sum1" = "$sum2" ]
}
