#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
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
    # Extension whitelist applies in copy mode; symlink mode follows the repo
    # tree wholesale, so the WARN/skip semantic only exists for --copy.
    echo "binary-ish" > "$FAKE_REPO/templates/unknown.xyz"
    run_install --copy
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
    run_install --copy
    [ "$status" -eq 0 ]
    grep -q "existing edit" "$FAKE_CLAUDE/agents/planner.md"
}

@test "T7 merge mode: new files still copied even when others exist" {
    seed_live_runtime
    run_install --copy
    [ "$status" -eq 0 ]
    [ -f "$FAKE_CLAUDE/skills/testing/SKILL.md" ]
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
    [ ! -d "$FAKE_CLAUDE/backups" ] || ! compgen -G "$FAKE_CLAUDE/backups/force-*" >/dev/null
}

@test "T10 AC-2 --force --yes on live system: backup created with SUCCESS marker" {
    # Legacy --force backup path applies to copy mode only; symlink mode
    # delegates backup creation to migrate_to_symlinks (see T33-5).
    seed_live_runtime
    run_install --copy --force --yes
    [ "$status" -eq 0 ]
    [ -d "$FAKE_CLAUDE/backups" ]
    local backup
    backup="$(ls -d "$FAKE_CLAUDE"/backups/force-* 2>/dev/null | head -1)"
    [ -n "$backup" ]
    [ -f "$backup/SUCCESS" ]
    [ -f "$backup/agents/planner.md" ]
}

@test "T10b AC-2 --force --yes: pre-existing file is overwritten after backup" {
    seed_live_runtime
    echo "# existing edit" > "$FAKE_CLAUDE/agents/planner.md"
    run_install --copy --force --yes
    [ "$status" -eq 0 ]
    local backup
    backup="$(ls -d "$FAKE_CLAUDE"/backups/force-* 2>/dev/null | head -1)"
    grep -q "existing edit" "$backup/agents/planner.md"
    run ! grep -q "existing edit" "$FAKE_CLAUDE/agents/planner.md"
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
    [ -f "$FAKE_CLAUDE/skills/testing/SKILL.md" ]
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

# ============================================================================
# TUNE-0033: symlink-default + local/ overlay
# ============================================================================

# ---------- AC-1: symlink-default fresh install ----------

@test "T33-1 AC-1 fresh install creates symlinks for all 4 scopes (default mode)" {
    run_install
    [ "$status" -eq 0 ]
    assert_symlink_to "$FAKE_CLAUDE/agents"    "$FAKE_REPO/agents"
    assert_symlink_to "$FAKE_CLAUDE/skills"    "$FAKE_REPO/skills"
    assert_symlink_to "$FAKE_CLAUDE/commands"  "$FAKE_REPO/commands"
    assert_symlink_to "$FAKE_CLAUDE/templates" "$FAKE_REPO/templates"
}

@test "T33-2 AC-1 fresh install creates local/ overlay with 4 scope dirs + .gitignore" {
    run_install
    [ "$status" -eq 0 ]
    [ -d "$FAKE_CLAUDE/local/skills" ]
    [ -d "$FAKE_CLAUDE/local/agents" ]
    [ -d "$FAKE_CLAUDE/local/commands" ]
    [ -d "$FAKE_CLAUDE/local/templates" ]
    [ -f "$FAKE_CLAUDE/local/.gitignore" ]
    grep -q '^\*$' "$FAKE_CLAUDE/local/.gitignore"
}

# ---------- AC-2: --copy fallback ----------

@test "T33-3 AC-2 --copy creates real copies, not symlinks" {
    run_install --copy
    [ "$status" -eq 0 ]
    [ ! -L "$FAKE_CLAUDE/agents" ]
    [ -d "$FAKE_CLAUDE/agents" ]
    [ -f "$FAKE_CLAUDE/agents/planner.md" ]
    # local/ overlay still set up under copy mode.
    [ -d "$FAKE_CLAUDE/local/skills" ]
}

# ---------- AC-3: platform auto-detection ----------

@test "T33-4 AC-3 MSYSTEM=MINGW64 forces copy mode (Windows fallback)" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" \
        DATARIM_FORCE_UNAME=MINGW64_NT-10 \
        "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 0 ]
    [ ! -L "$FAKE_CLAUDE/agents" ]
    [ -f "$FAKE_CLAUDE/agents/planner.md" ]
    [[ "$output" == *"copy"* ]]
}

# ---------- AC-4: migration prompt (3 options) ----------

@test "T33-5 AC-4(c) migration --yes converts copy → symlinks with backup" {
    seed_existing_copy_install
    # Mark with a unique edit we can recognise in the backup.
    mkdir -p "$(dirname "$FAKE_CLAUDE/skills/testing/SKILL.md")"
    echo "# user edit before migrate" > "$FAKE_CLAUDE/skills/testing/SKILL.md"
    run_install --yes
    [ "$status" -eq 0 ]
    # Result: symlinks now in place
    assert_symlink_to "$FAKE_CLAUDE/skills" "$FAKE_REPO/skills"
    # Backup directory exists with migrate-* prefix and SUCCESS marker
    local backup
    backup="$(ls -d "$FAKE_CLAUDE"/backups/migrate-* 2>/dev/null | head -1)"
    [ -n "$backup" ]
    [ -f "$backup/SUCCESS" ]
    grep -q "scopes_migrated=" "$backup/SUCCESS"
    # Original user content preserved in backup
    grep -q "user edit before migrate" "$backup/skills/testing/SKILL.md"
}

@test "T33-6 AC-4(k) migration with INSTALL_CHOICE=k keeps copy mode" {
    seed_existing_copy_install
    mkdir -p "$(dirname "$FAKE_CLAUDE/skills/testing/SKILL.md")"
    echo "# user content" > "$FAKE_CLAUDE/skills/testing/SKILL.md"
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" \
        DATARIM_MIGRATION_CHOICE=k \
        "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 0 ]
    # Skills remains a real dir (not symlink)
    [ ! -L "$FAKE_CLAUDE/skills" ]
    [ -d "$FAKE_CLAUDE/skills" ]
    # User content preserved (merge mode, no overwrite)
    grep -q "user content" "$FAKE_CLAUDE/skills/testing/SKILL.md"
    # No migration backup created
    [ ! -d "$FAKE_CLAUDE/backups" ] || ! ls "$FAKE_CLAUDE"/backups/migrate-* >/dev/null 2>&1
}

@test "T33-7 AC-4(a) migration with INSTALL_CHOICE=a aborts cleanly" {
    seed_existing_copy_install
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" \
        DATARIM_MIGRATION_CHOICE=a \
        "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 1 ]
    # No symlinks, no backups
    [ ! -L "$FAKE_CLAUDE/skills" ]
    [ ! -d "$FAKE_CLAUDE/backups" ] || ! ls "$FAKE_CLAUDE"/backups/migrate-* >/dev/null 2>&1
}

# ---------- AC-5: --force under symlinks is a no-op ----------

@test "T33-8 AC-5 --force under existing symlinks: no-op, no backup" {
    # First: clean install (creates symlinks)
    run_install
    [ "$status" -eq 0 ]
    # Second: --force --yes — should detect symlinks and exit without backup
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" \
        "$FAKE_REPO/install.sh" --force --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"symlink"* || "$output" == *"Already"* || "$output" == *"nothing to update"* ]]
    # No backup directory created — symlink mode skips backup
    [ ! -d "$FAKE_CLAUDE/backups" ] || ! ls "$FAKE_CLAUDE"/backups/force-* >/dev/null 2>&1
}

# ---------- dev-tools/ is a first-class install scope ----------

@test "T34 dev-tools/ is installed as a symlink (symlink mode)" {
    # Create a fake dev-tools/ tree in the source repo (mirrors real layout).
    mkdir -p "$FAKE_REPO/dev-tools/tests"
    echo '#!/bin/sh' > "$FAKE_REPO/dev-tools/doc-fanout-lint.sh"
    echo "version: 1" > "$FAKE_REPO/dev-tools/.doc-fanout.yml"
    echo "# bats" > "$FAKE_REPO/dev-tools/tests/doc-fanout-lint.bats"
    run_install
    [ "$status" -eq 0 ]
    # Post-install: dev-tools resolves to the source tree (runtime IS repo).
    assert_symlink_to "$FAKE_CLAUDE/dev-tools" "$FAKE_REPO/dev-tools"
}

@test "T35 dev-tools/ is installed as a real dir (copy mode)" {
    mkdir -p "$FAKE_REPO/dev-tools"
    echo '#!/bin/sh' > "$FAKE_REPO/dev-tools/doc-fanout-lint.sh"
    run_install --copy
    [ "$status" -eq 0 ]
    # Copy mode materialises dev-tools as a real directory, not a symlink.
    [ -d "$FAKE_CLAUDE/dev-tools" ]
    [ ! -L "$FAKE_CLAUDE/dev-tools" ]
    [ -f "$FAKE_CLAUDE/dev-tools/doc-fanout-lint.sh" ]
}

@test "T36 INSTALL_SCOPES whitelist includes dev-tools" {
    # Static contract assertion: dev-tools is a member of INSTALL_SCOPES.
    grep -E '^INSTALL_SCOPES=' "$FAKE_REPO/install.sh" | grep -q 'dev-tools'
    [ "$?" -eq 0 ]
}

# ---------- TUNE-0193: symlink idempotency + dry-run guards ----------

# Helper: test link_scope_tree in isolation by extracting the function from
# install.sh and calling it directly. We source install.sh in a subshell
# that skips the main flow to avoid side effects.
run_link_scope_tree() {
    local src="$1" dst="$2"
    # Extract link_scope_tree function and run it in a clean subshell.
    bash -c "
        set -euo pipefail
        LINKED=0
        DRY_RUN=${DRY_RUN:-false}
        $(sed -n '/^link_scope_tree()/,/^}/p' "$FAKE_REPO/install.sh")
        link_scope_tree \"$src\" \"$dst\"
    "
}

@test "TUNE-0193-01 dangling symlink is relinked (not skipped as already)" {
    # Pre-create a dangling symlink at commands/.
    mkdir -p "$(dirname "$FAKE_CLAUDE/commands")"
    ln -s "/nonexistent/path/commands" "$FAKE_CLAUDE/commands"
    # Do the same for agents, skills, templates so topology = symlink.
    ln -s "/nonexistent/path/agents"    "$FAKE_CLAUDE/agents"
    ln -s "/nonexistent/path/skills"    "$FAKE_CLAUDE/skills"
    ln -s "/nonexistent/path/templates" "$FAKE_CLAUDE/templates"
    [ ! -e "$FAKE_CLAUDE/commands" ]  # dangling — target doesn't exist

    run_install
    [ "$status" -eq 0 ]

    # After install: symlink is valid and points to the correct source.
    assert_symlink_to "$FAKE_CLAUDE/commands" "$FAKE_REPO/commands"
    [ -e "$FAKE_CLAUDE/commands" ]
    [ -f "$FAKE_CLAUDE/commands/dr-init.md" ]
}

@test "TUNE-0193-02 link_scope_tree refuses to overwrite real directory" {
    # Create a real directory with content at the commands/ scope.
    mkdir -p "$FAKE_CLAUDE/commands"
    echo "# hand-written" > "$FAKE_CLAUDE/commands/manual.md"

    # Call link_scope_tree directly — should exit 1.
    run run_link_scope_tree "$FAKE_REPO/commands" "$FAKE_CLAUDE/commands"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* || "$output" == *"real directory"* ]]

    # Real directory and its content are untouched.
    [ -d "$FAKE_CLAUDE/commands" ]
    [ -f "$FAKE_CLAUDE/commands/manual.md" ]
    grep -q "hand-written" "$FAKE_CLAUDE/commands/manual.md"
}

@test "TUNE-0193-03 --dry-run skips all filesystem mutations" {
    # Capture filesystem state before.
    local before_agents before_skills before_commands before_templates
    [ ! -d "$FAKE_CLAUDE/agents" ]    || before_agents="exists"
    [ ! -d "$FAKE_CLAUDE/skills" ]    || before_skills="exists"
    [ ! -d "$FAKE_CLAUDE/commands" ]  || before_commands="exists"
    [ ! -d "$FAKE_CLAUDE/templates" ] || before_templates="exists"

    run_install --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY"* ]]

    # Nothing was created on disk.
    if [ -z "$before_agents" ]; then
        [ ! -d "$FAKE_CLAUDE/agents" ]
    fi
    if [ -z "$before_skills" ]; then
        [ ! -d "$FAKE_CLAUDE/skills" ]
    fi
    if [ -z "$before_commands" ]; then
        [ ! -d "$FAKE_CLAUDE/commands" ]
    fi
    if [ -z "$before_templates" ]; then
        [ ! -d "$FAKE_CLAUDE/templates" ]
    fi
    # No symlinks were created.
    [ ! -L "$FAKE_CLAUDE/agents" ]
    [ ! -L "$FAKE_CLAUDE/skills" ]
    [ ! -L "$FAKE_CLAUDE/commands" ]
    [ ! -L "$FAKE_CLAUDE/templates" ]
}

@test "TUNE-0193-04 idempotent re-run: valid symlink → LINK (already)" {
    # First install creates symlinks.
    run_install
    [ "$status" -eq 0 ]
    assert_symlink_to "$FAKE_CLAUDE/commands" "$FAKE_REPO/commands"

    # Second install should report LINK (already) for each scope.
    run_install
    [ "$status" -eq 0 ]
    [[ "$output" == *"LINK (already)"* ]]

    # Symlinks are still valid.
    assert_symlink_to "$FAKE_CLAUDE/commands" "$FAKE_REPO/commands"
}
