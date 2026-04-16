# install_fixture.bash
# Shared setup for install.bats and check-drift.bats tests (TUNE-0004).
#
# Builds a minimal fake repo under $BATS_TEST_TMPDIR/fake-repo/ that mirrors
# the real framework layout (4 install scopes + VERSION + install.sh) and a
# clean fake CLAUDE_DIR under $BATS_TEST_TMPDIR/fake-claude/.
#
# The real install.sh and check-drift.sh under test are copied in at setup
# time — each test is isolated. HOME is redirected to a tmpdir so that any
# accidental fallback to "$HOME/.claude" cannot touch the operator's real
# runtime (defense in depth, Law 1).

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup_fixture() {
    export FAKE_REPO="$BATS_TEST_TMPDIR/fake-repo"
    export FAKE_CLAUDE="$BATS_TEST_TMPDIR/fake-claude"
    export FAKE_HOME="$BATS_TEST_TMPDIR/fake-home"
    mkdir -p "$FAKE_REPO"/{agents,skills,commands,templates,scripts,tests}
    mkdir -p "$FAKE_HOME"

    echo "1.9.0-test" > "$FAKE_REPO/VERSION"

    # Seed each install scope with one canonical .md file.
    echo "# planner" > "$FAKE_REPO/agents/planner.md"
    echo "# testing" > "$FAKE_REPO/skills/testing.md"
    echo "# dr-init"  > "$FAKE_REPO/commands/dr-init.md"
    echo "# prd"     > "$FAKE_REPO/templates/prd-template.md"

    # Supporting subdirectory in skills/ (mimics skills/datarim-system/).
    mkdir -p "$FAKE_REPO/skills/sub-dir"
    echo "# fragment" > "$FAKE_REPO/skills/sub-dir/frag.md"

    # Non-.md content types — the whole point of TUNE-0004.
    cat > "$FAKE_REPO/templates/deploy.sh" <<'SH'
#!/bin/bash
echo "deploy stub"
SH
    echo '{"k":"v"}' > "$FAKE_REPO/templates/config.json"

    # Copy scripts under test.
    cp "$REPO_ROOT/install.sh" "$FAKE_REPO/install.sh"
    chmod +x "$FAKE_REPO/install.sh"

    if [ -f "$REPO_ROOT/scripts/check-drift.sh" ]; then
        cp "$REPO_ROOT/scripts/check-drift.sh" "$FAKE_REPO/scripts/check-drift.sh"
        chmod +x "$FAKE_REPO/scripts/check-drift.sh"
    fi
}

# Populate FAKE_CLAUDE with existing content so is_live_system() returns true.
seed_live_runtime() {
    mkdir -p "$FAKE_CLAUDE"/{agents,skills,commands,templates}
    echo "# pre-existing runtime" > "$FAKE_CLAUDE/agents/planner.md"
}

# Run install.sh with FAKE_CLAUDE and redirected HOME. bats captures no TTY
# by default — which is exactly the non-TTY scenario we want for most tests.
run_install() {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/install.sh" "$@"
}

# Emulate TTY via `script -q` where available (macOS BSD `script`). Used only
# where TTY behaviour matters; falls back to piping "yes\n" if script missing.
run_install_with_tty_input() {
    local input="$1"; shift
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" bash -c "printf '%s\n' \"$input\" | \"$FAKE_REPO/install.sh\" $*"
}
