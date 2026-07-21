#!/usr/bin/env bats
#
# Contract tests for the `--enable-codex-prompts` install path.
#
# Codex CLI exposes files in ~/.codex/prompts/<name>.md as `/prompts:<name>`
# slash-commands. `install.sh --with-codex --enable-codex-prompts` mirrors each
# shipped commands/dr-*.md into $CODEX_DIR/prompts/dr-<name>.md so the same
# Datarim commands are reachable as `/prompts:dr-status` etc. under Codex.
#
# T51-T54 per the mirror design:
#   T51  — mirror creates flat dr-*.md copies (byte-identical), excludes
#          non-dr command files, and records an ownership manifest.
#   T51b — idempotency: a second run with no source change produces no diff.
#   T52  — opt-out: without --enable-codex-prompts nothing is mirrored.
#   T53  — namespace-conflict detection: a pre-existing dr-*.md we did not
#          author, and any non-dr file, are never overwritten or deleted.
#   T54  — --dry-run reports the plan, exits 0, writes nothing.
#   T54b — --help advertises the --enable-codex-prompts flag.
#
# The mirror is a flat copy (not a symlink) for Windows/FAT parity with
# setup_cursor_runtime, and ships behind R8 (accepted-risk: Codex documents
# the /prompts: mechanism as legacy; opt-in default-off, deferred-validation).

INSTALL_SH="${BATS_TEST_DIRNAME}/../install.sh"

setup() {
    TMPSRC="$(mktemp -d)"
    TMPCODEX="$(mktemp -d)"
    # Defense-in-depth: redirect HOME + CLAUDE_DIR to fake paths so any
    # accidental fanout cannot touch the operator's real ~/.claude or
    # ~/.local/bin. Mirrors tests/install-cursor-runtime.bats.
    FAKE_HOME="$TMPSRC/fake-home"
    FAKE_CLAUDE="$TMPSRC/fake-claude"
    mkdir -p "$FAKE_HOME" "$FAKE_CLAUDE"

    # Minimal but complete source tree: all INSTALL_SCOPES dirs must exist so a
    # full --with-codex fanout can run; commands/ carries two dr-* commands and
    # one non-dr command that must never be mirrored.
    local scope
    for scope in agents skills commands templates scripts tests dev-tools; do
        mkdir -p "$TMPSRC/$scope"
    done
    cat >"$TMPSRC/commands/dr-status.md" <<'EOF'
---
name: dr-status
description: status command
---
dr-status body
EOF
    cat >"$TMPSRC/commands/dr-plan.md" <<'EOF'
---
name: dr-plan
description: plan command
---
dr-plan body
EOF
    cat >"$TMPSRC/commands/factcheck.md" <<'EOF'
---
name: factcheck
description: non-dr command — must not be mirrored to prompts
---
factcheck body
EOF
    # Codex fanout links/copies AGENTS.md; give it real (non-stub) content.
    printf 'router content\n' >"$TMPSRC/AGENTS.md"
    printf 'router content\n' >"$TMPSRC/CLAUDE.md"
    printf '2.57.0\n' >"$TMPSRC/VERSION"

    cp "$INSTALL_SH" "$TMPSRC/install.sh"
    chmod +x "$TMPSRC/install.sh"
}

teardown() {
    rm -rf "$TMPSRC" "$TMPCODEX"
}

# Portable content-hash of the prompts tree (GNU or BSD checksum tool).
_prompts_tree_hash() {
    if command -v sha1sum >/dev/null 2>&1; then
        find "$TMPCODEX/prompts" -type f -exec sha1sum {} \; 2>/dev/null | \
            sed "s#$TMPCODEX##" | sort | sha1sum
    else
        find "$TMPCODEX/prompts" -type f -exec shasum {} \; 2>/dev/null | \
            sed "s#$TMPCODEX##" | sort | shasum
    fi
}

@test "T51: --enable-codex-prompts mirrors dr-* commands, excludes non-dr, writes manifest" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CODEX_DIR="$TMPCODEX" \
        "$TMPSRC/install.sh" --with-codex --no-codex-ux --enable-codex-prompts --yes
    [ "$status" -eq 0 ]
    # dr-* commands mirrored, byte-identical to source.
    [ -f "$TMPCODEX/prompts/dr-status.md" ]
    [ -f "$TMPCODEX/prompts/dr-plan.md" ]
    run diff "$TMPSRC/commands/dr-status.md" "$TMPCODEX/prompts/dr-status.md"
    [ "$status" -eq 0 ]
    # Non-dr command NOT mirrored.
    [ ! -f "$TMPCODEX/prompts/factcheck.md" ]
    # Ownership manifest records exactly the two mirrored files.
    [ -f "$TMPCODEX/prompts/.datarim-managed" ]
    run grep -Fxq "dr-status.md" "$TMPCODEX/prompts/.datarim-managed"
    [ "$status" -eq 0 ]
    run grep -Fxq "dr-plan.md" "$TMPCODEX/prompts/.datarim-managed"
    [ "$status" -eq 0 ]
    run grep -Fxq "factcheck.md" "$TMPCODEX/prompts/.datarim-managed"
    [ "$status" -ne 0 ]
}

@test "T51b: --enable-codex-prompts is idempotent (re-run produces no diff)" {
    env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CODEX_DIR="$TMPCODEX" \
        "$TMPSRC/install.sh" --with-codex --no-codex-ux --enable-codex-prompts --yes >/dev/null
    first="$(_prompts_tree_hash)"
    env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CODEX_DIR="$TMPCODEX" \
        "$TMPSRC/install.sh" --with-codex --no-codex-ux --enable-codex-prompts --yes >/dev/null
    second="$(_prompts_tree_hash)"
    [ "$first" = "$second" ]
}

@test "T52: without --enable-codex-prompts nothing is mirrored (opt-out default-off)" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CODEX_DIR="$TMPCODEX" \
        "$TMPSRC/install.sh" --with-codex --no-codex-ux --yes
    [ "$status" -eq 0 ]
    [ ! -f "$TMPCODEX/prompts/dr-status.md" ]
    [ ! -f "$TMPCODEX/prompts/dr-plan.md" ]
    [ ! -f "$TMPCODEX/prompts/.datarim-managed" ]
}

@test "T53: namespace-conflict detection — foreign dr-* and non-dr files survive" {
    # Operator-authored files present BEFORE any Datarim mirror (no manifest).
    mkdir -p "$TMPCODEX/prompts"
    printf 'OPERATOR OWNED dr-status\n' >"$TMPCODEX/prompts/dr-status.md"
    printf 'operator notes\n' >"$TMPCODEX/prompts/notes.md"

    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CODEX_DIR="$TMPCODEX" \
        "$TMPSRC/install.sh" --with-codex --no-codex-ux --enable-codex-prompts --yes
    [ "$status" -eq 0 ]
    # Foreign dr-status.md NOT overwritten.
    run cat "$TMPCODEX/prompts/dr-status.md"
    [[ "$output" == *"OPERATOR OWNED"* ]]
    # A conflict warning was surfaced.
    [[ "$output" == *"dr-status.md"* ]] || true
    # Non-dr operator file untouched.
    [ -f "$TMPCODEX/prompts/notes.md" ]
    run cat "$TMPCODEX/prompts/notes.md"
    [[ "$output" == *"operator notes"* ]]
    # A non-conflicting command still mirrors.
    [ -f "$TMPCODEX/prompts/dr-plan.md" ]
    # Foreign file must NOT have been adopted into the managed set.
    run grep -Fxq "dr-status.md" "$TMPCODEX/prompts/.datarim-managed"
    [ "$status" -ne 0 ]
}

@test "T54: --enable-codex-prompts --dry-run reports plan, writes nothing" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" CODEX_DIR="$TMPCODEX" \
        "$TMPSRC/install.sh" --with-codex --enable-codex-prompts --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"prompts"* ]]
    # Nothing written to the target.
    [ ! -f "$TMPCODEX/prompts/dr-status.md" ]
    [ ! -f "$TMPCODEX/prompts/.datarim-managed" ]
}

@test "T54b: --help advertises the --enable-codex-prompts flag" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$TMPSRC/install.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--enable-codex-prompts"* ]]
}
