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
    chmod +x "$FAKE_REPO/templates/deploy.sh"
    echo '{"k":"v"}' > "$FAKE_REPO/templates/config.json"

    # Copy scripts under test.
    cp "$REPO_ROOT/install.sh" "$FAKE_REPO/install.sh"
    chmod +x "$FAKE_REPO/install.sh"

    if [ -f "$REPO_ROOT/scripts/check-drift.sh" ]; then
        cp "$REPO_ROOT/scripts/check-drift.sh" "$FAKE_REPO/scripts/check-drift.sh"
        chmod +x "$FAKE_REPO/scripts/check-drift.sh"
    fi
}

# TUNE-0033: copy update.sh, validate.sh, curate-runtime.sh into FAKE_REPO.
# Called separately so existing tests (that don't need these) stay light.
setup_full_scripts() {
    if [ -f "$REPO_ROOT/update.sh" ]; then
        cp "$REPO_ROOT/update.sh" "$FAKE_REPO/update.sh"
        chmod +x "$FAKE_REPO/update.sh"
    fi
    if [ -f "$REPO_ROOT/validate.sh" ]; then
        cp "$REPO_ROOT/validate.sh" "$FAKE_REPO/validate.sh"
        chmod +x "$FAKE_REPO/validate.sh"
    fi
    if [ -f "$REPO_ROOT/scripts/curate-runtime.sh" ]; then
        cp "$REPO_ROOT/scripts/curate-runtime.sh" "$FAKE_REPO/scripts/curate-runtime.sh"
        chmod +x "$FAKE_REPO/scripts/curate-runtime.sh"
    fi
    # validate.sh greps CLAUDE.md for skill names — provide a minimal one
    # mentioning all fixture file basenames so warnings stay quiet.
    cat > "$FAKE_REPO/CLAUDE.md" <<'CLAUDE'
# Test fixture CLAUDE.md
References: planner, testing, dr-init, prd-template, deploy, config, frag.
CLAUDE
}

# TUNE-0033: seed FAKE_CLAUDE as a fully populated real-copy install,
# mimicking a v1.16 user upgrading to v1.17. Used by migration-prompt tests.
seed_existing_copy_install() {
    mkdir -p "$FAKE_CLAUDE"/{agents,skills,commands,templates}
    echo "# pre-existing planner" > "$FAKE_CLAUDE/agents/planner.md"
    echo "# pre-existing testing" > "$FAKE_CLAUDE/skills/testing.md"
    echo "# pre-existing dr-init" > "$FAKE_CLAUDE/commands/dr-init.md"
    echo "# pre-existing prd-template" > "$FAKE_CLAUDE/templates/prd-template.md"
}

# TUNE-0033: assert that $1 is a symlink resolving to absolute path $2.
# Both sides are canonicalised through `cd -P` to handle macOS /private/var
# vs /var symlink prefixes uniformly.
assert_symlink_to() {
    local link="$1" expected="$2" resolved expected_canon
    [ -L "$link" ] || { echo "Not a symlink: $link" >&2; return 1; }
    resolved="$(cd -P "$link" 2>/dev/null && pwd)"
    expected_canon="$(cd -P "$expected" 2>/dev/null && pwd)"
    [ "$resolved" = "$expected_canon" ] || {
        echo "Symlink target mismatch: $resolved != $expected_canon" >&2
        return 1
    }
}

# TUNE-0033: emulate already-symlinked CLAUDE_DIR (post-migration topology).
seed_symlink_install() {
    rm -rf "$FAKE_CLAUDE"/{agents,skills,commands,templates}
    mkdir -p "$FAKE_CLAUDE"
    local s
    for s in agents skills commands templates; do
        ln -s "$FAKE_REPO/$s" "$FAKE_CLAUDE/$s"
    done
}

# TUNE-0033: turn FAKE_REPO into a git repo with a local bare origin so
# update.sh's `git pull origin main` succeeds with no changes.
init_fake_git_with_origin() {
    (
        cd "$FAKE_REPO"
        git init -q -b main 2>/dev/null || git init -q
        git config user.email "test@example.com"
        git config user.name "Test User"
        git add -A
        git commit -q -m "init" >/dev/null 2>&1 || true
        git branch -m main 2>/dev/null || true
        local origin="$BATS_TEST_TMPDIR/origin.git"
        rm -rf "$origin"
        git clone --bare -q . "$origin" >/dev/null 2>&1
        git remote remove origin 2>/dev/null || true
        git remote add origin "$origin"
    ) >/dev/null 2>&1
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
