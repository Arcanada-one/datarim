#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."

@test "Claude and Codex mandate fragment resolves coworker delegation per workspace" {
    grep -qF 'coworker-delegation-state.sh' "$REPO/templates/coworker-delegation-fragment.md" \
        && grep -qF 'enabled' "$REPO/templates/coworker-delegation-fragment.md" \
        && grep -qF 'disabled' "$REPO/templates/coworker-delegation-fragment.md"
}

@test "Cursor rule resolves the same enabled and disabled states" {
    grep -qF 'coworker-delegation-state.sh' "$REPO/templates/coworker-delegation.mdc" \
        && grep -qF 'enabled' "$REPO/templates/coworker-delegation.mdc" \
        && grep -qF 'disabled' "$REPO/templates/coworker-delegation.mdc"
}

@test "disabled instructions permit native I/O without removing quality gates" {
    grep -qF 'native agent I/O is permitted' "$REPO/templates/coworker-delegation-fragment.md" \
        && grep -qF 'does not disable unrelated safety or quality gates' \
            "$REPO/templates/coworker-delegation-fragment.md" \
        && grep -qF 'native agent I/O is permitted' "$REPO/templates/coworker-delegation.mdc"
}

@test "resolver failure and non-exact output retain delegation" {
    grep -qF 'Only an exact `disabled` result deactivates' \
        "$REPO/templates/coworker-delegation-fragment.md" \
        && grep -qF 'Only an exact `disabled` result deactivates' \
            "$REPO/templates/coworker-delegation.mdc"
}

@test "hook guard consumes the same workspace resolver" {
    grep -qF 'coworker-delegation-state.sh' "$REPO/dev-tools/coworker-hook-guard.sh" \
        && grep -qF 'delegation_disabled_for_workspace' \
            "$REPO/dev-tools/coworker-hook-guard.sh"
}

@test "touched hook surface contains no Cyrillic operator text" {
    ! grep -nP '\p{Cyrillic}' "$REPO/dev-tools/coworker-hook-guard.sh"
}

@test "plugin documentation states default-on and no-install boundary" {
    grep -qiF 'enabled by default' "$REPO/plugins/coworker-delegation/README.md" \
        && grep -qF 'does not install, remove, configure, or call `coworker`' \
            "$REPO/plugins/coworker-delegation/README.md"
}

@test "installer advertises the reserved coworker toggle by CLI identity" {
    local target="$BATS_TEST_TMPDIR/claude"

    run env HOME="$BATS_TEST_TMPDIR/home" CLAUDE_DIR="$target" \
        bash "$REPO/install.sh" --with-claude --copy --yes

    [ "$status" -eq 0 ] || return 1
    [[ "$output" == *"/dr-plugin enable coworker-delegation"* ]] || return 1
    [[ "$output" != *"/dr-plugin enable $REPO/plugins/coworker-delegation"* ]]
}

@test "public framework docs link the coworker delegation toggle how-to" {
    [ -f "$REPO/documentation/how-to/coworker-delegation-toggle.md" ] \
        && grep -qF 'coworker-delegation-toggle.md' "$REPO/commands/dr-plugin.md" \
        && grep -qF 'coworker-delegation-toggle.md' "$REPO/README.md" \
        && grep -qF 'coworker-delegation' "$REPO/CLAUDE.md"
}
