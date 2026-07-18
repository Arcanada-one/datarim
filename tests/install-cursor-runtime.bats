#!/usr/bin/env bats
#
# TUNE-0304 Phase 4: contract tests for --with-cursor install path.
#
# T47-T50 per plan §6.5:
#   T47 — `install.sh --with-cursor --dry-run` reports planned Cursor paths,
#         exits 0, writes nothing.
#   T48 — `install.sh --with-cursor` against an isolated CURSOR_DIR creates
#         ~/.cursor/skills/<name>.md flat files for each migrated skill
#         and exits 0.
#   T49 — idempotency: re-running --with-cursor with no source changes
#         produces no diff on the target.
#   T50 — `--help` advertises the --with-cursor flag and CURSOR_DIR env var.
#
# Cursor's discovery semantics are not officially documented as of
# 2026-Q2; the install creates flat .md mirrors of skills/<name>/SKILL.md
# (one file per skill). This ships behind R7 (accepted-risk: deferred
# Cursor-runtime smoke; operator validates on real Cursor install).

INSTALL_SH="${BATS_TEST_DIRNAME}/../install.sh"

setup() {
    TMPSRC="$(mktemp -d)"
    TMPCURSOR="$(mktemp -d)"
    # Defense-in-depth: redirect HOME + CLAUDE_DIR to fake paths so any
    # accidental fanout into the claude scope cannot touch the operator's
    # real ~/.claude. Mirrors the contract in tests/install-tune-0114.bats
    # and tests/install.bats (helpers/install_fixture.bash).
    FAKE_HOME="$TMPSRC/fake-home"
    FAKE_CLAUDE="$TMPSRC/fake-claude"
    mkdir -p "$FAKE_HOME" "$FAKE_CLAUDE"
    # Minimal source tree: two migrated skills + one .system skill.
    mkdir -p "$TMPSRC/skills/alpha" "$TMPSRC/skills/beta" "$TMPSRC/skills/.system/bundled"
    mkdir -p "$TMPSRC/scripts/lib" "$TMPSRC/commands"
    cp "$BATS_TEST_DIRNAME/../scripts/tdd-enforcement-state.sh" "$TMPSRC/scripts/tdd-enforcement-state.sh"
    cp "$BATS_TEST_DIRNAME/../scripts/ltm-graph-memory-state.sh" "$TMPSRC/scripts/ltm-graph-memory-state.sh"
    cp "$BATS_TEST_DIRNAME/../scripts/lib/plugin-system.sh" "$TMPSRC/scripts/lib/plugin-system.sh"
    cp "$BATS_TEST_DIRNAME/../commands/dr-do.md" "$TMPSRC/commands/dr-do.md"
    cp "$BATS_TEST_DIRNAME/../commands/dr-prd.md" "$TMPSRC/commands/dr-prd.md"
    cat >"$TMPSRC/skills/alpha/SKILL.md" <<'EOF'
---
name: alpha
description: alpha skill
---
alpha body
EOF
    cat >"$TMPSRC/skills/beta/SKILL.md" <<'EOF'
---
name: beta
description: beta skill
---
beta body
EOF
    cat >"$TMPSRC/skills/.system/bundled/SKILL.md" <<'EOF'
---
name: bundled
description: codex bundled
---
EOF
    # install.sh resolves paths via dirname; copy it into a sibling of TMPSRC
    # so it can locate skills/ next to itself.
    cp "$INSTALL_SH" "$TMPSRC/install.sh"
    chmod +x "$TMPSRC/install.sh"
}

teardown() {
    rm -rf "$TMPSRC" "$TMPCURSOR"
}

@test "T47: --with-cursor --dry-run reports planned paths, writes nothing" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CURSOR_DIR="$TMPCURSOR" "$TMPSRC/install.sh" --with-cursor --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"cursor"* ]] || [[ "$output" == *"Cursor"* ]]
    # Target untouched.
    [ ! -e "$TMPCURSOR/skills/alpha.md" ]
}

@test "T48: --with-cursor creates flat .md mirrors of each skill" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CURSOR_DIR="$TMPCURSOR" "$TMPSRC/install.sh" --with-cursor --yes
    [ "$status" -eq 0 ]
    [ -f "$TMPCURSOR/skills/alpha.md" ]
    [ -f "$TMPCURSOR/skills/beta.md" ]
    run cat "$TMPCURSOR/skills/alpha.md"
    [[ "$output" == *"name: alpha"* ]]
    [[ "$output" == *"alpha body"* ]]
}

@test "T48b: --with-cursor excludes skills/.system/ namespace (C3)" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CURSOR_DIR="$TMPCURSOR" "$TMPSRC/install.sh" --with-cursor --yes
    [ "$status" -eq 0 ]
    [ ! -f "$TMPCURSOR/skills/bundled.md" ]
    [ ! -d "$TMPCURSOR/skills/.system" ]
}

@test "T48c: --with-cursor installs the shared TDD enforcement resolver" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CURSOR_DIR="$TMPCURSOR" "$TMPSRC/install.sh" --with-cursor --yes
    [ "$status" -eq 0 ] \
        && [ -x "$TMPCURSOR/scripts/tdd-enforcement-state.sh" ] \
        && [ -f "$TMPCURSOR/scripts/lib/plugin-system.sh" ]
}

@test "T48c2: --with-cursor installs the shared LTM graph-memory resolver" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CURSOR_DIR="$TMPCURSOR" "$TMPSRC/install.sh" --with-cursor --yes
    [ "$status" -eq 0 ] \
        && [ -x "$TMPCURSOR/scripts/ltm-graph-memory-state.sh" ] \
        && [ -f "$TMPCURSOR/scripts/lib/plugin-system.sh" ]
}

@test "T48c3: missing LTM source does not suppress established TDD fanout" {
    mv "$TMPSRC/scripts/ltm-graph-memory-state.sh" \
        "$TMPSRC/scripts/ltm-graph-memory-state.sh.missing"

    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CURSOR_DIR="$TMPCURSOR" \
        "$TMPSRC/install.sh" --with-cursor --yes

    [ "$status" -eq 0 ] \
        && [ -x "$TMPCURSOR/scripts/tdd-enforcement-state.sh" ] \
        && [ -f "$TMPCURSOR/scripts/lib/plugin-system.sh" ] \
        && [ ! -e "$TMPCURSOR/scripts/ltm-graph-memory-state.sh" ]
}

@test "T48d: Cursor-only install has an automatic resolver fallback" {
    local default_cursor="$FAKE_HOME/.cursor"
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CURSOR_DIR="$default_cursor" \
        "$TMPSRC/install.sh" --with-cursor --yes
    [ "$status" -eq 0 ] || return 1
    grep -q '\$HOME/.cursor' "$default_cursor/commands/dr-do.md" || return 1
    mkdir -p "$FAKE_HOME/workspace/datarim"
    run env -u DATARIM_RUNTIME HOME="$FAKE_HOME" bash -c '
        for root in "${DATARIM_RUNTIME:-}" "$HOME/.claude" "$HOME/.codex" "$HOME/.cursor"; do
            [ -n "$root" ] || continue
            if [ -x "$root/scripts/tdd-enforcement-state.sh" ]; then
                exec bash "$root/scripts/tdd-enforcement-state.sh" --workspace "$HOME/workspace"
            fi
        done
        exit 2
    '
    [ "$status" -eq 0 ] && [ "$output" = "required" ]
}

@test "T48e: Cursor-only install resolves graph memory disabled by default" {
    local default_cursor="$FAKE_HOME/.cursor"
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CURSOR_DIR="$default_cursor" \
        "$TMPSRC/install.sh" --with-cursor --yes
    [ "$status" -eq 0 ] || return 1
    grep -q 'ltm-graph-memory-state.sh' "$default_cursor/commands/dr-prd.md" || return 1
    mkdir -p "$FAKE_HOME/workspace/datarim"
    run env -u DATARIM_RUNTIME HOME="$FAKE_HOME" bash -c '
        for root in "${DATARIM_RUNTIME:-}" "$HOME/.claude" "$HOME/.codex" "$HOME/.cursor"; do
            [ -n "$root" ] || continue
            if [ -x "$root/scripts/ltm-graph-memory-state.sh" ]; then
                exec bash "$root/scripts/ltm-graph-memory-state.sh" --workspace "$HOME/workspace"
            fi
        done
        exit 2
    '
    [ "$status" -eq 0 ] && [ "$output" = "disabled" ]
}

@test "T49: --with-cursor is idempotent (re-run produces no diff)" {
    env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CURSOR_DIR="$TMPCURSOR" "$TMPSRC/install.sh" --with-cursor --yes >/dev/null
    sha1_first=$(find "$TMPCURSOR/skills" -type f -exec sha1sum {} \; 2>/dev/null | \
                 sort | sha1sum 2>/dev/null || \
                 find "$TMPCURSOR/skills" -type f -exec shasum {} \; | sort | shasum)
    env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CURSOR_DIR="$TMPCURSOR" "$TMPSRC/install.sh" --with-cursor --yes >/dev/null
    sha1_second=$(find "$TMPCURSOR/skills" -type f -exec sha1sum {} \; 2>/dev/null | \
                  sort | sha1sum 2>/dev/null || \
                  find "$TMPCURSOR/skills" -type f -exec shasum {} \; | sort | shasum)
    [ "$sha1_first" = "$sha1_second" ]
}

@test "T50: --help advertises --with-cursor flag" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$TMPSRC/install.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--with-cursor"* ]]
}

@test "T51 regression: --with-cursor --yes does not fanout into \$CLAUDE_DIR" {
    # Operator-reported regression — the backwards-compat block in install.sh
    # implicitly enabled FANOUT_CLAUDE=true on --yes/--force without checking
    # FANOUT_CURSOR. Combined with the missing HOME isolation that this file
    # carried before this commit, it left the operator's real ~/.claude
    # symlinks pointing at the deleted bats tmp source dir.
    #
    # Contract: --with-cursor [--yes] MUST leave $CLAUDE_DIR untouched.
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CURSOR_DIR="$TMPCURSOR" \
        "$TMPSRC/install.sh" --with-cursor --yes
    [ "$status" -eq 0 ]
    # Cursor side did its job.
    [ -f "$TMPCURSOR/skills/alpha.md" ]
    # Claude side must be untouched — no symlinks, no real dirs.
    for scope in agents skills commands templates scripts tests dev-tools; do
        [ ! -e "$FAKE_CLAUDE/$scope" ]
    done
}
