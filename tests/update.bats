#!/usr/bin/env bats
#
# Tests for update.sh under TUNE-0033 (symlink-default + local/ overlay).
#
# AC-6 contract:
#   - Symlink mode → git pull only, exit 0, no install step.
#   - Copy    mode → git pull + install --force --yes --copy.

load 'helpers/install_fixture'

setup() {
    setup_fixture
    setup_full_scripts
    init_fake_git_with_origin
}

@test "U1 AC-6 update.sh under symlink mode skips install step (exit 0)" {
    seed_symlink_install
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/update.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ymlink"* ]]
    # Install step is skipped — no "Installing scope..." messages.
    [[ "$output" != *"Installing agents"* ]]
    [[ "$output" != *"Installing skills"* ]]
}

@test "U2 AC-6 update.sh under copy mode runs install --force --yes --copy" {
    seed_existing_copy_install
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/update.sh"
    [ "$status" -eq 0 ]
    # Installation step ran (proper install message visible)
    [[ "$output" == *"Installing"* || "$output" == *"Copied"* ]]
    # Runtime stays in copy mode — agents/ is still a real dir, not a symlink.
    [ ! -L "$FAKE_CLAUDE/agents" ]
    [ -d "$FAKE_CLAUDE/agents" ]
}
