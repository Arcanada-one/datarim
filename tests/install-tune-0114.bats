#!/usr/bin/env bats
# tests/install-tune-0114.bats — Phase 2 multi-runtime install gate (TUNE-0114).
#
# Covers plan §5 Go/No-Go:
#   - no flags = print usage, exit 0 (D2)
#   - --with-codex creates ~/.codex/skills symlink
#   - --with-claude --with-codex installs both runtimes
#   - --project DIR copies into DIR/.datarim
#   - validate_project_dir rejects /etc /usr /bin /sbin /System (exit 3)
#   - --dry-run produces zero mutations
#   - concurrent runs blocked by lockfile (exit 4)

load 'helpers/install_fixture'

setup() {
    setup_fixture
}

teardown() {
    rm -f /tmp/.install-tune-0114-* 2>/dev/null || true
}

# ---------- D2: no flags = usage ------------------------------------------

@test "TUNE-0114 D2 no flags prints usage and exits 0 without installing" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
    # No install side-effects: no scopes created
    [ ! -e "$FAKE_CLAUDE/agents" ]
    [ ! -e "$FAKE_CLAUDE/skills" ]
}

# ---------- --with-codex --------------------------------------------------

@test "TUNE-0114 --with-codex creates ~/.codex with all 6 scopes (symlink mode)" {
    local fake_codex="$FAKE_HOME/.codex"
    run env HOME="$FAKE_HOME" CODEX_DIR="$fake_codex" "$FAKE_REPO/install.sh" --with-codex
    [ "$status" -eq 0 ]
    assert_symlink_to "$fake_codex/agents"    "$FAKE_REPO/agents"
    assert_symlink_to "$fake_codex/skills"    "$FAKE_REPO/skills"
    assert_symlink_to "$fake_codex/commands"  "$FAKE_REPO/commands"
    assert_symlink_to "$fake_codex/templates" "$FAKE_REPO/templates"
    assert_symlink_to "$fake_codex/scripts"   "$FAKE_REPO/scripts"
    assert_symlink_to "$fake_codex/tests"     "$FAKE_REPO/tests"
}

@test "TUNE-0114 --with-claude --with-codex installs both runtimes" {
    local fake_codex="$FAKE_HOME/.codex"
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CODEX_DIR="$fake_codex" \
        "$FAKE_REPO/install.sh" --with-claude --with-codex
    [ "$status" -eq 0 ]
    assert_symlink_to "$FAKE_CLAUDE/skills" "$FAKE_REPO/skills"
    assert_symlink_to "$fake_codex/skills"  "$FAKE_REPO/skills"
}

# ---------- --project copy mode -------------------------------------------

@test "TUNE-0114 --project copies all 6 scopes + CLAUDE.md into DIR/.datarim" {
    local proj="$FAKE_HOME/myproj"
    mkdir -p "$proj"
    # fixture seeds scope dirs but not CLAUDE.md; project_install copies it.
    echo "# fake CLAUDE.md" > "$FAKE_REPO/CLAUDE.md"
    run env HOME="$FAKE_HOME" "$FAKE_REPO/install.sh" --project "$proj"
    [ "$status" -eq 0 ]
    [ -d "$proj/.datarim/agents" ]
    [ -d "$proj/.datarim/skills" ]
    [ -d "$proj/.datarim/commands" ]
    [ -d "$proj/.datarim/templates" ]
    [ -d "$proj/.datarim/scripts" ]
    [ -d "$proj/.datarim/tests" ]
    [ -f "$proj/.datarim/CLAUDE.md" ]
    # Real files, not symlinks
    [ ! -L "$proj/.datarim/skills" ]
}

@test "TUNE-0114 --project /etc rejected with exit 3" {
    run env HOME="$FAKE_HOME" "$FAKE_REPO/install.sh" --project /etc
    [ "$status" -eq 3 ]
    [[ "$output" == *"unsafe"* ]] || [[ "$output" == *"reject"* ]]
}

@test "TUNE-0114 --project /usr rejected with exit 3" {
    run env HOME="$FAKE_HOME" "$FAKE_REPO/install.sh" --project /usr
    [ "$status" -eq 3 ]
}

@test "TUNE-0114 --project /System rejected with exit 3" {
    run env HOME="$FAKE_HOME" "$FAKE_REPO/install.sh" --project /System
    [ "$status" -eq 3 ]
}

@test "TUNE-0114 --project requires argument (exit 2)" {
    run env HOME="$FAKE_HOME" "$FAKE_REPO/install.sh" --project
    [ "$status" -eq 2 ]
}

# ---------- --dry-run -----------------------------------------------------

@test "TUNE-0114 --dry-run --with-claude produces no mutations" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" \
        "$FAKE_REPO/install.sh" --with-claude --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY:"* ]]
    # No symlinks/dirs created (other than the parent CLAUDE_DIR which acquire_lock mkdirs)
    [ ! -e "$FAKE_CLAUDE/agents" ]
    [ ! -e "$FAKE_CLAUDE/skills" ]
}

@test "TUNE-0114 --dry-run --with-codex produces no mutations" {
    local fake_codex="$FAKE_HOME/.codex"
    run env HOME="$FAKE_HOME" CODEX_DIR="$fake_codex" \
        "$FAKE_REPO/install.sh" --with-codex --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY:"* ]]
    [ ! -e "$fake_codex/agents" ]
}

# ---------- lockfile concurrency ------------------------------------------

@test "TUNE-0114 stale lockfile blocks concurrent install with exit 4" {
    mkdir -p "$FAKE_CLAUDE"
    echo 99999 > "$FAKE_CLAUDE/.install.lock"  # simulate held lock
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" \
        "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 4 ]
    [[ "$output" == *"lockfile busy"* ]] || [[ "$output" == *"lockfile"* ]]
}

# ---------- backwards-compat layer ----------------------------------------

@test "TUNE-0114 legacy --copy without --with-claude implies claude with WARN" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" \
        "$FAKE_REPO/install.sh" --copy
    [ "$status" -eq 0 ]
    # Stderr WARN about deprecation
    [[ "$output" == *"WARN"* ]] || [[ "$output" == *"deprecated"* ]] || [[ "$output" == *"implicit"* ]]
    # Install actually happened
    [ -d "$FAKE_CLAUDE/agents" ]
}
