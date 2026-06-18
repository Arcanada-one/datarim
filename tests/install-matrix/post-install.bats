#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
#
# Post-install assertions for the Docker matrix harness.
#
# Each lane of install-matrix.sh runs this suite inside the container after
# install.sh completes.  The tests are intentionally vendor-aware: they
# inspect TARGET_DIR (the directory install.sh actually wrote to) and branch
# on VENDOR_FLAG so assertions match each vendor's real post-install contract.
#
# Environment variables injected by the lane:
#   TARGET_DIR   — path to the directory install.sh wrote into (vendor-specific)
#   VENDOR_FLAG  — e.g. "--with-claude", "--with-codex", "--with-cursor"
#   INSTALL_REPO — path to the cloned datarim repo inside the container
#
# Vendor → target dir mapping (set by install-matrix.sh):
#   --with-claude  → $CLAUDE_DIR  (default ~/.claude)   — 7-scope symlink layout
#   --with-codex   → $CODEX_DIR   (default ~/.codex)    — 7-scope layout + AGENTS.md + AGENTS.override.md
#   --with-cursor  → $CURSOR_DIR  (default ~/.cursor)   — flat skills mirror (skills/<name>.md)
#
# These tests do NOT assume the operator's host directories — they use
# TARGET_DIR which is set to a container-local scratch dir by the harness.
#
# V-AC-2 contract (claude): agents, skills, commands, templates, scripts, tests, dev-tools

# ---------- setup: resolve paths ----------------------------------------------

setup() {
    # These assertions run INSIDE a matrix container, after install.sh has
    # populated TARGET_DIR from a clone at INSTALL_REPO. When invoked directly
    # on a host (naive `bats tests/`) neither is set up, so skip rather than
    # false-fail — the matrix driver exports both before calling.
    if [ -z "${TARGET_DIR:-}" ] || [ -z "${INSTALL_REPO:-}" ]; then
        skip "matrix-only: set TARGET_DIR and INSTALL_REPO (driven by install-matrix.sh inside a container)"
    fi
    [ -d "$TARGET_DIR" ] || skip "TARGET_DIR ($TARGET_DIR) absent — run via install-matrix.sh"
    [ -d "$INSTALL_REPO" ] || skip "INSTALL_REPO ($INSTALL_REPO) absent — run via install-matrix.sh"
}

# ---------- scope presence (claude + codex only) ------------------------------

@test "agents scope present after install" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor) skip "cursor installs a flat skills mirror — no 7-scope layout" ;;
    esac
    [ -e "$TARGET_DIR/agents" ]
}

@test "skills scope present after install" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor) skip "cursor installs a flat skills mirror — no 7-scope layout" ;;
    esac
    [ -e "$TARGET_DIR/skills" ]
}

@test "commands scope present after install" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor) skip "cursor does not install a top-level commands/ scope" ;;
    esac
    [ -e "$TARGET_DIR/commands" ]
}

@test "templates scope present after install" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor) skip "cursor does not install a templates/ scope" ;;
    esac
    [ -e "$TARGET_DIR/templates" ]
}

@test "scripts scope present after install" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor) skip "cursor does not install a scripts/ scope" ;;
    esac
    [ -e "$TARGET_DIR/scripts" ]
}

@test "tests scope present after install" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor) skip "cursor does not install a tests/ scope" ;;
    esac
    [ -e "$TARGET_DIR/tests" ]
}

@test "dev-tools scope present after install" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor) skip "cursor does not install a dev-tools/ scope" ;;
    esac
    [ -e "$TARGET_DIR/dev-tools" ]
}

# ---------- key file reachability (claude + codex) ----------------------------

@test "planner agent reachable via TARGET_DIR" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor) skip "cursor does not install agents/ scope" ;;
    esac
    [ -f "$TARGET_DIR/agents/planner.md" ]
}

@test "datarim-system skill reachable via TARGET_DIR" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor) skip "cursor uses flat skills mirror — check cursor-specific assertion instead" ;;
    esac
    [ -f "$TARGET_DIR/skills/datarim-system/SKILL.md" ]
}

@test "dr-init command reachable via TARGET_DIR" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor)
            # cursor mirrors commands into TARGET_DIR/commands/dr-init.md
            [ -f "$TARGET_DIR/commands/dr-init.md" ]
            return
            ;;
    esac
    [ -f "$TARGET_DIR/commands/dr-init.md" ]
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

# ---------- symlink topology (claude + codex — default symlink mode) ----------

@test "agents scope is a symlink or real directory" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor) skip "cursor does not install agents/ scope" ;;
    esac
    [ -L "$TARGET_DIR/agents" ] || [ -d "$TARGET_DIR/agents" ]
}

@test "dev-tools scope is a symlink or real directory" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor) skip "cursor does not install dev-tools/ scope" ;;
    esac
    [ -L "$TARGET_DIR/dev-tools" ] || [ -d "$TARGET_DIR/dev-tools" ]
}

# ---------- codex-specific assertions -----------------------------------------

@test "codex: AGENTS.md present in TARGET_DIR" {
    case "${VENDOR_FLAG:-}" in
        --with-codex) ;;
        *) skip "AGENTS.md contract is codex-specific" ;;
    esac
    [ -e "$TARGET_DIR/AGENTS.md" ]
}

@test "codex: AGENTS.override.md present in TARGET_DIR" {
    case "${VENDOR_FLAG:-}" in
        --with-codex) ;;
        *) skip "AGENTS.override.md contract is codex-specific" ;;
    esac
    [ -f "$TARGET_DIR/AGENTS.override.md" ]
}

@test "codex: skills/ is a real directory (not a symlink) under codex-ux" {
    case "${VENDOR_FLAG:-}" in
        --with-codex) ;;
        *) skip "codex skills-dir-shape contract is codex-specific" ;;
    esac
    # With --with-codex (default FANOUT_CODEX_UX=true) skills/ must be a real
    # directory containing per-skill SKILL.md wrappers.
    [ -d "$TARGET_DIR/skills" ] && [ ! -L "$TARGET_DIR/skills" ]
}

@test "codex: at least one skill wrapper (SKILL.md) generated under skills/" {
    case "${VENDOR_FLAG:-}" in
        --with-codex) ;;
        *) skip "codex SKILL.md wrapper contract is codex-specific" ;;
    esac
    found=0
    for f in "$TARGET_DIR/skills"/*/SKILL.md; do
        [ -f "$f" ] && found=1 && break
    done
    [ "$found" -eq 1 ]
}

# ---------- cursor-specific assertions ----------------------------------------

@test "cursor: flat skills mirror present (skills/<name>.md)" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor) ;;
        *) skip "flat skills mirror contract is cursor-specific" ;;
    esac
    # At least one <name>.md file must exist directly under TARGET_DIR/skills/.
    found=0
    for f in "$TARGET_DIR/skills/"*.md; do
        [ -f "$f" ] && found=1 && break
    done
    [ "$found" -eq 1 ]
}

@test "cursor: datarim-system skill mirrored as flat file" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor) ;;
        *) skip "flat skill mirror is cursor-specific" ;;
    esac
    [ -f "$TARGET_DIR/skills/datarim-system.md" ]
}

@test "cursor: ai-quality skill mirrored as flat file" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor) ;;
        *) skip "flat skill mirror is cursor-specific" ;;
    esac
    [ -f "$TARGET_DIR/skills/ai-quality.md" ]
}

@test "cursor: no 7-scope subdirectory layout in TARGET_DIR root" {
    case "${VENDOR_FLAG:-}" in
        --with-cursor) ;;
        *) skip "layout-absence check is cursor-specific" ;;
    esac
    # cursor must NOT have an agents/ directory at the root (it uses flat skills).
    [ ! -d "$TARGET_DIR/agents" ]
}
