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
    # --no-codex-ux preserves TUNE-0114 baseline contract (uniform symlinks).
    # Default (with TUNE-0297 fanout_codex_ux) converts skills/ to a real dir;
    # TUNE-0297 T42 covers that contract.
    run env HOME="$FAKE_HOME" CODEX_DIR="$fake_codex" "$FAKE_REPO/install.sh" --with-codex --no-codex-ux
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
        "$FAKE_REPO/install.sh" --with-claude --with-codex --no-codex-ux
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

# ---------- TUNE-0296: AGENTS.md routing for Codex CLI --------------------

@test "TUNE-0296 T40 --with-codex creates AGENTS.md symlink to Datarim source" {
    local fake_codex="$FAKE_HOME/.codex"
    echo "# datarim AGENTS" > "$FAKE_REPO/AGENTS.md"
    run env HOME="$FAKE_HOME" CODEX_DIR="$fake_codex" "$FAKE_REPO/install.sh" --with-codex
    [ "$status" -eq 0 ]
    [ -L "$fake_codex/AGENTS.md" ]
    local actual expected
    actual="$(readlink "$fake_codex/AGENTS.md")"
    expected="$FAKE_REPO/AGENTS.md"
    [ "$actual" = "$expected" ] || { echo "AGENTS.md symlink target: '$actual' != '$expected'" >&2; false; }
    [ "$(cat "$fake_codex/AGENTS.md")" = "# datarim AGENTS" ]
}

@test "TUNE-0296 T41 --with-claude does NOT create AGENTS.md (regression guard)" {
    echo "# datarim AGENTS" > "$FAKE_REPO/AGENTS.md"
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 0 ]
    [ ! -e "$FAKE_CLAUDE/AGENTS.md" ]
}

@test "TUNE-0296 T40b --with-codex --dry-run mentions AGENTS.md, --with-claude --dry-run does not" {
    local fake_codex="$FAKE_HOME/.codex"
    echo "# datarim AGENTS" > "$FAKE_REPO/AGENTS.md"
    run env HOME="$FAKE_HOME" CODEX_DIR="$fake_codex" \
        "$FAKE_REPO/install.sh" --with-codex --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"AGENTS.md"* ]]

    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" \
        "$FAKE_REPO/install.sh" --with-claude --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" != *"AGENTS.md"* ]]
}

# ---------- TUNE-0297: Codex UX parity (SKILL.md wrappers + AGENTS.override) ----

@test "TUNE-0297 T42 --with-codex generates SKILL.md wrapper for each source skill" {
    local fake_codex="$FAKE_HOME/.codex"
    echo "# datarim AGENTS" > "$FAKE_REPO/AGENTS.md"
    mkdir -p "$(dirname "$FAKE_REPO/skills/testing/SKILL.md")"
    cat > "$FAKE_REPO/skills/testing/SKILL.md" <<'MD'
---
name: testing
description: Testing pyramid and mocking rules
---

# Testing

Body.
MD
    run env HOME="$FAKE_HOME" CODEX_DIR="$fake_codex" "$FAKE_REPO/install.sh" --with-codex
    [ "$status" -eq 0 ]
    [ -f "$fake_codex/skills/testing/SKILL.md" ]
    # Frontmatter contains name + description (always double-quoted post YAML-safe fix)
    grep -qE '^name: "?testing"?' "$fake_codex/skills/testing/SKILL.md"
    grep -qE '^description: "' "$fake_codex/skills/testing/SKILL.md"
    # Body references source path
    grep -q 'code/datarim/skills/' "$fake_codex/skills/testing/SKILL.md"
    # Sub-dir source (skills/sub-dir/frag.md) does NOT get a wrapper at top level
    [ ! -e "$fake_codex/skills/frag/SKILL.md" ]
    [ ! -e "$fake_codex/skills/sub-dir/SKILL.md" ]
}

@test "TUNE-0297 T43 --with-claude does NOT create SKILL.md wrappers under fake_codex" {
    local fake_codex="$FAKE_HOME/.codex"
    echo "# datarim AGENTS" > "$FAKE_REPO/AGENTS.md"
    mkdir -p "$(dirname "$FAKE_REPO/skills/testing/SKILL.md")"
    cat > "$FAKE_REPO/skills/testing/SKILL.md" <<'MD'
---
name: testing
description: t
---
body
MD
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 0 ]
    # claude install must not touch ~/.codex at all
    [ ! -e "$fake_codex/skills/testing/SKILL.md" ]
    [ ! -e "$fake_codex/AGENTS.override.md" ]
}

@test "TUNE-0297 T44 --with-codex writes AGENTS.override.md and leaves AGENTS.md byte-stable" {
    local fake_codex="$FAKE_HOME/.codex"
    cat > "$FAKE_REPO/AGENTS.md" <<'AG'
# datarim AGENTS canonical

Stable router content.
AG
    local src_sha
    src_sha="$(shasum -a 256 "$FAKE_REPO/AGENTS.md" | awk '{print $1}')"
    mkdir -p "$(dirname "$FAKE_REPO/skills/testing/SKILL.md")"
    cat > "$FAKE_REPO/skills/testing/SKILL.md" <<'MD'
---
name: testing
description: t
---
MD
    run env HOME="$FAKE_HOME" CODEX_DIR="$fake_codex" "$FAKE_REPO/install.sh" --with-codex
    [ "$status" -eq 0 ]
    [ -f "$fake_codex/AGENTS.override.md" ]
    grep -q '^## Available Datarim Commands' "$fake_codex/AGENTS.override.md"
    grep -q '^## Available Datarim Skills' "$fake_codex/AGENTS.override.md"
    grep -q '^## Available Datarim Agents' "$fake_codex/AGENTS.override.md"
    # Manifest has at least one /dr- entry (fixture seeds commands/dr-init.md)
    local entries
    entries="$(grep -c '^- ' "$fake_codex/AGENTS.override.md" || true)"
    [ "$entries" -ge 3 ]
    # AGENTS.md (the symlink) resolves to the source file — content must match byte-for-byte
    [ -L "$fake_codex/AGENTS.md" ]
    local post_sha
    post_sha="$(shasum -a 256 "$fake_codex/AGENTS.md" | awk '{print $1}')"
    [ "$src_sha" = "$post_sha" ] || { echo "AGENTS.md drifted: pre=$src_sha post=$post_sha" >&2; false; }
}

@test "TUNE-0297 T45 --with-codex restores .system/ from bundled-backup when present" {
    local fake_codex="$FAKE_HOME/.codex"
    local backup="$fake_codex/skills.bundled-backup-TUNE-0296-20260524T195336Z"
    mkdir -p "$backup/.system/skill-installer/scripts"
    echo "# skill-installer source" > "$backup/.system/skill-installer/SKILL.md"
    echo "print('list')" > "$backup/.system/skill-installer/scripts/list-skills.py"
    mkdir -p "$backup/.system/imagegen"
    echo "# imagegen" > "$backup/.system/imagegen/SKILL.md"
    echo "# datarim AGENTS" > "$FAKE_REPO/AGENTS.md"
    mkdir -p "$(dirname "$FAKE_REPO/skills/testing/SKILL.md")"
    cat > "$FAKE_REPO/skills/testing/SKILL.md" <<'MD'
---
name: testing
description: t
---
MD
    run env HOME="$FAKE_HOME" CODEX_DIR="$fake_codex" "$FAKE_REPO/install.sh" --with-codex
    [ "$status" -eq 0 ]
    [ -f "$fake_codex/skills/.system/skill-installer/SKILL.md" ]
    [ -f "$fake_codex/skills/.system/skill-installer/scripts/list-skills.py" ]
    [ -f "$fake_codex/skills/.system/imagegen/SKILL.md" ]
    # idempotency — rerun shouldn't change shasum of the resulting tree
    local sum1 sum2
    sum1="$(find "$fake_codex/skills" -type f | sort | xargs shasum -a 256 | shasum -a 256 | awk '{print $1}')"
    run env HOME="$FAKE_HOME" CODEX_DIR="$fake_codex" "$FAKE_REPO/install.sh" --with-codex
    [ "$status" -eq 0 ]
    sum2="$(find "$fake_codex/skills" -type f | sort | xargs shasum -a 256 | shasum -a 256 | awk '{print $1}')"
    [ "$sum1" = "$sum2" ] || { echo "idempotency broken: $sum1 != $sum2" >&2; false; }
}

@test "TUNE-0297 T46 --with-codex --no-codex-ux opts out of wrapper generation" {
    local fake_codex="$FAKE_HOME/.codex"
    echo "# datarim AGENTS" > "$FAKE_REPO/AGENTS.md"
    mkdir -p "$(dirname "$FAKE_REPO/skills/testing/SKILL.md")"
    cat > "$FAKE_REPO/skills/testing/SKILL.md" <<'MD'
---
name: testing
description: t
---
MD
    run env HOME="$FAKE_HOME" CODEX_DIR="$fake_codex" "$FAKE_REPO/install.sh" --with-codex --no-codex-ux
    [ "$status" -eq 0 ]
    # AGENTS.md symlink still set (TUNE-0296 baseline)
    [ -L "$fake_codex/AGENTS.md" ]
    # No UX artefacts:
    #   - skills/ is a plain symlink to the source tree (uniform Datarim
    #     baseline), NOT a real directory populated with generated wrappers
    #     (which is what fanout_codex_ux would produce under TUNE-0297).
    [ -L "$fake_codex/skills" ]
    # AGENTS.override.md is the canonical fanout_codex_ux artefact — absent
    # under --no-codex-ux.
    [ ! -e "$fake_codex/AGENTS.override.md" ]
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
