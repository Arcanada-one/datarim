#!/usr/bin/env bats
# Container matrix contract. Ordinary discovery reports the missing lane context.
setup() {
    if [ -z "${TARGET_DIR:-}" ] || [ -z "${INSTALL_REPO:-}" ]; then
        skip "not measured: run dev-tools/install-matrix.sh for distribution lanes"
    fi
}

@test "matrix: pinned project runtime and canonical instructions exist" {
    [ -f "$TARGET_DIR/.datarim-runtime/installation.json" ]
    [ -f "$TARGET_DIR/AGENTS.md" ]
    [ ! -L "$TARGET_DIR/AGENTS.md" ]
    [ ! -e "$TARGET_DIR/CLAUDE.md" ]
}

@test "matrix: selected vendor discovers project skill directories" {
    case "$VENDOR_FLAG" in
        claude) discovery=.claude ;;
        codex) discovery=.agents ;;
        cursor) discovery=.cursor ;;
    esac
    [ -f "$TARGET_DIR/$discovery/skills/testing/SKILL.md" ]
    [ -f "$TARGET_DIR/$discovery/skills/dr-do/SKILL.md" ]
}

@test "matrix: no global framework discovery was installed" {
    [ ! -e "$HOME/.claude/skills" ]
    [ ! -e "$HOME/.codex/skills" ]
    [ ! -e "$HOME/.cursor/skills" ]
}

@test "matrix: update is idempotent and source paths remain pinned" {
    run sh "$INSTALL_REPO/update.sh" --project "$TARGET_DIR" --with-jev --init
    [ "$status" -eq 0 ]
    [[ "$output" == *'"status": "unchanged"'* ]]
}
