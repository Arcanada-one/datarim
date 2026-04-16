#!/usr/bin/env bats
#
# Tests for install.sh (TUNE-0004).
#
# Contract under test (from datarim/tasks.md TUNE-0004 Implementation Plan):
#   - AC-1: installer copies .md, .sh, .json, .yaml, .yml from all 4 scopes
#   - AC-2: --force detects live system, requires "yes" confirm or --yes flag,
#           creates backup under $CLAUDE_DIR/backups/force-{ISO}/ with SUCCESS marker
#   - AC-5: bats coverage for merge / force / content-type / idempotency
#   - AC-7: .md-only repos install identically to v1.8.0 (no regression)
#
# Security:
#   - Every test runs in BATS_TEST_TMPDIR with HOME redirected to a fake dir.
#   - CLAUDE_DIR=/ and CLAUDE_DIR="$HOME" cases exercise the sanity guard
#     BEFORE any filesystem mutation — defense-in-depth for Law 1.

load 'helpers/install_fixture'

setup() {
    setup_fixture
}

# ---------- AC-1: content-type support ----------

@test "T1 AC-1 fresh CLAUDE_DIR: .md file copied into agents/" {
    run_install
    [ "$status" -eq 0 ]
    [ -f "$FAKE_CLAUDE/agents/planner.md" ]
}

@test "T2 AC-1 fresh CLAUDE_DIR: .sh template copied AND executable" {
    run_install
    [ "$status" -eq 0 ]
    [ -f "$FAKE_CLAUDE/templates/deploy.sh" ]
    [ -x "$FAKE_CLAUDE/templates/deploy.sh" ]
}

@test "T3 AC-1 fresh CLAUDE_DIR: .json template copied" {
    run_install
    [ "$status" -eq 0 ]
    [ -f "$FAKE_CLAUDE/templates/config.json" ]
}

@test "T4 AC-1 unknown .xyz extension skipped with WARN in output" {
    # The unknown-ext file is local to this test so check-drift tests remain
    # drift-free after a full install of the standard fixture.
    echo "binary-ish" > "$FAKE_REPO/templates/unknown.xyz"
    run_install
    [ "$status" -eq 0 ]
    [ ! -f "$FAKE_CLAUDE/templates/unknown.xyz" ]
    [[ "$output" == *"unknown.xyz"* ]]
    [[ "$output" == *"WARN"* || "$output" == *"warn"* ]]
}

@test "T5 AC-1 supporting subdirectory preserved (skills/sub-dir/frag.md)" {
    run_install
    [ "$status" -eq 0 ]
    [ -f "$FAKE_CLAUDE/skills/sub-dir/frag.md" ]
}

# ---------- merge mode ----------

@test "T6 merge mode: existing file skipped (no overwrite without --force)" {
    seed_live_runtime
    echo "# existing edit" > "$FAKE_CLAUDE/agents/planner.md"
    run_install
    [ "$status" -eq 0 ]
    grep -q "existing edit" "$FAKE_CLAUDE/agents/planner.md"
}

@test "T7 merge mode: new files still copied even when others exist" {
    seed_live_runtime
    run_install
    [ "$status" -eq 0 ]
    [ -f "$FAKE_CLAUDE/skills/testing.md" ]
    [ -f "$FAKE_CLAUDE/templates/deploy.sh" ]
}

# ---------- AC-2: --force safety guard ----------

@test "T8 AC-2 --force on fresh CLAUDE_DIR: no prompt, no backup (not live)" {
    run_install --force
    [ "$status" -eq 0 ]
    [ ! -d "$FAKE_CLAUDE/backups" ]
}

@test "T9 AC-2 --force on live system, non-TTY, no --yes: exit 1 refuse" {
    seed_live_runtime
    run_install --force
    [ "$status" -eq 1 ]
    [[ "$output" == *"non-TTY"* || "$output" == *"TTY"* || "$output" == *"tty"* ]]
    # No backup created because install aborted BEFORE copy phase.
    [ ! -d "$FAKE_CLAUDE/backups" ] || ! ls "$FAKE_CLAUDE/backups" 2>/dev/null | grep -q force-
}

@test "T10 AC-2 --force --yes on live system: backup created with SUCCESS marker" {
    seed_live_runtime
    run_install --force --yes
    [ "$status" -eq 0 ]
    [ -d "$FAKE_CLAUDE/backups" ]
    # Exactly one force-* backup directory with SUCCESS marker inside.
    local backup
    backup="$(ls -d "$FAKE_CLAUDE"/backups/force-* 2>/dev/null | head -1)"
    [ -n "$backup" ]
    [ -f "$backup/SUCCESS" ]
    [ -f "$backup/agents/planner.md" ]
}

@test "T10b AC-2 --force --yes: pre-existing file is overwritten after backup" {
    seed_live_runtime
    echo "# existing edit" > "$FAKE_CLAUDE/agents/planner.md"
    run_install --force --yes
    [ "$status" -eq 0 ]
    # Old content preserved in backup.
    local backup
    backup="$(ls -d "$FAKE_CLAUDE"/backups/force-* 2>/dev/null | head -1)"
    grep -q "existing edit" "$backup/agents/planner.md"
    # Current runtime now has new content (seeded # planner from fixture).
    ! grep -q "existing edit" "$FAKE_CLAUDE/agents/planner.md"
    grep -q "^# planner" "$FAKE_CLAUDE/agents/planner.md"
}

@test "T11 AC-2 --force --yes with CLAUDE_DIR=/ refused with exit 2" {
    # Bypass the helper because we need CLAUDE_DIR=/ explicitly.
    run env HOME="$FAKE_HOME" CLAUDE_DIR="/" "$FAKE_REPO/install.sh" --force --yes
    [ "$status" -eq 2 ]
}

@test "T12 AC-2 --force --yes with CLAUDE_DIR=\$HOME refused with exit 2" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_HOME" "$FAKE_REPO/install.sh" --force --yes
    [ "$status" -eq 2 ]
}

@test "T12b AC-2 --force --yes with empty CLAUDE_DIR refused with exit 2" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="" "$FAKE_REPO/install.sh" --force --yes
    [ "$status" -eq 2 ]
}

# ---------- idempotency + regression ----------

@test "T13 idempotency: second run reports 0 copies, 0 errors" {
    run_install
    [ "$status" -eq 0 ]
    run_install
    [ "$status" -eq 0 ]
    # No Copied count > 0 on second run (merge mode skips everything).
    [[ "$output" == *"Copied: 0"* ]]
}

@test "T14 AC-7 regression: all 4 scopes populated with .md files" {
    run_install
    [ "$status" -eq 0 ]
    [ -f "$FAKE_CLAUDE/agents/planner.md" ]
    [ -f "$FAKE_CLAUDE/skills/testing.md" ]
    [ -f "$FAKE_CLAUDE/commands/dr-init.md" ]
    [ -f "$FAKE_CLAUDE/templates/prd-template.md" ]
}

# ---------- edge / usability ----------

@test "T15 --help prints usage and exits 0 without running install" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* || "$output" == *"usage"* ]]
    # Critical: --help must NOT have performed an install.
    [ ! -f "$FAKE_CLAUDE/agents/planner.md" ]
}

@test "T16 unknown flag exits 2" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh" --wtf
    [ "$status" -eq 2 ]
}
