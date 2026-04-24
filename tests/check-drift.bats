#!/usr/bin/env bats
#
# Tests for scripts/check-drift.sh (TUNE-0004).
#
# Contract under test:
#   - AC-3: check-drift.sh SCOPES must exactly match install.sh INSTALL_SCOPES.
#   - AC-4: repo-only dirs (scripts/, tests/) are deliberately NOT scanned —
#           they are dev tooling, not distributed to $CLAUDE_DIR.
#   - After TUNE-0004 installer fix, a .sh file in templates/ that was
#     previously causing permanent drift now syncs cleanly.
#
# Tmpdir isolation: all tests run against FAKE_REPO + FAKE_CLAUDE.

load 'helpers/install_fixture'

setup() {
    setup_fixture
}

# ---------- AC-3 alignment ----------

@test "D1 AC-3 after full install: check-drift exits 0 (runtime == repo)" {
    run_install
    [ "$status" -eq 0 ]
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/scripts/check-drift.sh" --quiet
    [ "$status" -eq 0 ]
}

@test "D2 AC-3 manual runtime edit creates drift (exit 1, file listed)" {
    run_install
    [ "$status" -eq 0 ]
    echo "# evolved in runtime" >> "$FAKE_CLAUDE/agents/planner.md"
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/scripts/check-drift.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"planner.md"* ]]
}

@test "D3 AC-3 .sh template no longer causes permanent drift (the TUNE-0004 fix)" {
    run_install
    [ "$status" -eq 0 ]
    # Before TUNE-0004 the .sh was never copied so check-drift would report it.
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/scripts/check-drift.sh" --quiet
    [ "$status" -eq 0 ]
}

# ---------- AC-4 repo-only dirs ----------

@test "D4 AC-4 scripts/ and tests/ differences are invisible to check-drift" {
    run_install
    [ "$status" -eq 0 ]
    # Create drift that SHOULD be ignored (simulating a dev-tool file only in repo).
    echo "# extra tooling" > "$FAKE_REPO/scripts/dev-only.sh"
    # We don't copy scripts/ to CLAUDE_DIR at all, so file-level diff would
    # surface it if check-drift were accidentally scanning scripts/.
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/scripts/check-drift.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"dev-only.sh"* ]]
}

@test "D5 AC-3 check-drift SCOPES list matches install.sh contract (static grep)" {
    # Static check: both scripts list the same 4 scopes.
    grep -E "^INSTALL_SCOPES=\\(agents skills commands templates\\)" "$FAKE_REPO/install.sh"
    grep -E "^SCOPES=\\(agents skills commands templates\\)" "$FAKE_REPO/scripts/check-drift.sh"
}

# ---------- TUNE-0030: Symlink detection ----------

@test "D6 TUNE-0030 symlink runtime dir → repo detected (exit 1, SYMLINK in output)" {
    run_install
    [ "$status" -eq 0 ]

    # Replace real runtime skills dir with symlink to repo skills
    rm -rf "$FAKE_CLAUDE/skills"
    ln -s "$FAKE_REPO/skills" "$FAKE_CLAUDE/skills"

    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$FAKE_REPO/scripts/check-drift.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"SYMLINK"* ]]
    [[ "$output" == *"drift detection impossible"* ]]
}
