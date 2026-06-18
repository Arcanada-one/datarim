#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
#
# Post-install assertions for the Docker matrix harness.
#
# Each lane of install-matrix.sh runs this suite inside the container after
# install.sh completes.  The tests are intentionally runtime-agnostic so the
# same file runs for every vendor flag (--with-claude, --with-codex, etc.).
#
# Environment variables injected by the lane:
#   CLAUDE_DIR   — path to the runtime directory used during install
#   VENDOR_FLAG  — e.g. "--with-claude", "--with-codex", "--with-cursor"
#   INSTALL_REPO — path to the cloned datarim repo inside the container
#
# These tests do NOT assume the operator's host ~/.claude — they use CLAUDE_DIR
# which is set to a container-local scratch dir by the harness.
#
# Required scopes (V-AC-2 contract):
#   agents, skills, commands, templates, scripts, tests, dev-tools
# Each scope must be either a symlink or a real directory — both modes are
# accepted here (symlink is default, copy mode is Linux-safe but not asserted).

# ---------- setup: resolve paths ----------------------------------------------

setup() {
    CLAUDE_DIR="${CLAUDE_DIR:-/tmp/fake-claude}"
    INSTALL_REPO="${INSTALL_REPO:-/opt/datarim}"
}

# ---------- scope presence ---------------------------------------------------

@test "agents scope present after install" {
    [ -e "$CLAUDE_DIR/agents" ]
}

@test "skills scope present after install" {
    [ -e "$CLAUDE_DIR/skills" ]
}

@test "commands scope present after install" {
    [ -e "$CLAUDE_DIR/commands" ]
}

@test "templates scope present after install" {
    [ -e "$CLAUDE_DIR/templates" ]
}

@test "scripts scope present after install" {
    [ -e "$CLAUDE_DIR/scripts" ]
}

@test "tests scope present after install" {
    [ -e "$CLAUDE_DIR/tests" ]
}

@test "dev-tools scope present after install" {
    [ -e "$CLAUDE_DIR/dev-tools" ]
}

# ---------- key file reachability -------------------------------------------

@test "planner agent reachable via CLAUDE_DIR" {
    [ -f "$CLAUDE_DIR/agents/planner.md" ]
}

@test "datarim-system skill reachable via CLAUDE_DIR" {
    [ -f "$CLAUDE_DIR/skills/datarim-system/SKILL.md" ]
}

@test "dr-init command reachable via CLAUDE_DIR" {
    [ -f "$CLAUDE_DIR/commands/dr-init.md" ]
}

# ---------- install.sh executable + bash preamble ---------------------------

@test "install.sh is executable in INSTALL_REPO" {
    [ -x "$INSTALL_REPO/install.sh" ]
}

@test "install.sh preamble: re-exec line present (POSIX guard)" {
    grep -q 'exec.*bash.*\$0' "$INSTALL_REPO/install.sh"
}

@test "install.sh preamble: bash-absent exit-2 line present" {
    grep -q 'exit 2' "$INSTALL_REPO/install.sh"
}

# ---------- symlink topology (default symlink mode) --------------------------

@test "agents scope is a symlink or real directory" {
    [ -L "$CLAUDE_DIR/agents" ] || [ -d "$CLAUDE_DIR/agents" ]
}

@test "dev-tools scope is a symlink or real directory" {
    [ -L "$CLAUDE_DIR/dev-tools" ] || [ -d "$CLAUDE_DIR/dev-tools" ]
}
