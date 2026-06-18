#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
#
# POSIX re-exec preflight tests for install.sh.
#
# Tests T-P1..T-P4 cover the preamble inserted at the top of install.sh that
# handles three scenarios:
#   - Invoked via `sh install.sh` on a system where bash exists on PATH:
#     the preamble re-execs the script under bash transparently.
#   - Invoked via `sh install.sh` on a system where bash is absent:
#     the preamble prints one actionable "requires bash" message and exits 2.
#   - Invoked via `bash install.sh` normally:
#     preamble is a no-op; the rest of install.sh runs byte-unchanged.
#   - BASH_VERSION is set (already in bash) but $1 check shows we are already
#     in bash — no re-exec loop.
#
# Portability: no grep -P; no \x{} character classes. BSD stat -f / GNU stat -c
# handled via probe-and-fallback in each test that needs file-mode checks.

load 'helpers/install_fixture'

setup() {
    setup_fixture
}

# ---------- T-P1: sh invocation with bash on PATH → re-exec succeeds ----------

@test "T-P1 posix-sh invocation: re-execs under bash and installs successfully" {
    # Run with a POSIX-only sh (dash when available; skip on macOS where /bin/sh
    # is bash-3 and would succeed without the re-exec preamble).
    local posix_sh
    posix_sh="$(command -v dash 2>/dev/null || true)"
    if [ -z "$posix_sh" ]; then
        skip "dash not on PATH; T-P1 requires a POSIX-only sh"
    fi
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" "$posix_sh" "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 0 ]
    # At least one scope symlink created confirms the real install ran.
    [ -e "$FAKE_CLAUDE/agents" ]
}

# ---------- T-P2: bash absent → actionable message + exit 2 ------------------

@test "T-P2 bash absent on PATH: prints actionable message and exits 2" {
    # Requires dash (a real POSIX sh that cannot run bash arrays without re-exec).
    local posix_sh
    posix_sh="$(command -v dash 2>/dev/null || true)"
    if [ -z "$posix_sh" ]; then
        skip "dash not on PATH; T-P2 requires a POSIX-only sh"
    fi
    # Restrict PATH so bash is fully unreachable — use ONLY our empty directory,
    # not /bin (which on macOS contains /bin/bash).
    local no_bash_dir="$BATS_TEST_TMPDIR/no-bash-bin"
    mkdir -p "$no_bash_dir"
    # Make 'command' and 'printf' available — they are shell built-ins in dash,
    # so no additional PATH entries needed.  We still need a minimal /usr/bin
    # for sanity (e.g. env itself) but explicitly exclude /bin so /bin/bash
    # is unreachable.
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" \
        PATH="$no_bash_dir:/usr/bin" \
        "$posix_sh" "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 2 ]
    # Message must mention bash and give actionable guidance.
    [[ "$output" == *"bash"* ]]
    [[ "$output" == *"install.sh"* || "$output" == *"bash install"* ]]
}

# ---------- T-P3: normal bash invocation → no re-exec, byte-unchanged path ---

@test "T-P3 bash invocation: no re-exec loop, install completes normally" {
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" bash "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 0 ]
    [ -e "$FAKE_CLAUDE/agents" ]
    # Output must NOT contain a re-exec announcement.
    [[ "$output" != *"re-exec"* ]]
}

# ---------- T-P4: already in bash (BASH_VERSION set) → no infinite loop ------

@test "T-P4 BASH_VERSION already set: preamble skips re-exec cleanly" {
    # When run under bash, BASH_VERSION is already set — the preamble should
    # detect this and skip the exec branch, preventing an infinite re-exec loop.
    # We verify indirectly: if the install completes without hanging and exits 0
    # the preamble correctly exited the re-exec branch on the first iteration.
    run timeout 10 \
        env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" \
        bash "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 0 ]
}

# ---------- T-P5: sh with custom BASH path via PATH override ------------------

@test "T-P5 sh invocation: custom bash location honoured via PATH" {
    # Put a wrapper named 'bash' in a custom bin dir that is a real bash.
    local custom_bin="$BATS_TEST_TMPDIR/custom-bin"
    mkdir -p "$custom_bin"
    # Symlink the system bash into our custom-bin as 'bash'
    local real_bash
    real_bash="$(command -v bash)"
    ln -sf "$real_bash" "$custom_bin/bash"
    run env HOME="$FAKE_HOME" CLAUDE_DIR="$FAKE_CLAUDE" \
        PATH="$custom_bin:/usr/bin:/bin" \
        sh "$FAKE_REPO/install.sh" --with-claude
    [ "$status" -eq 0 ]
    [ -e "$FAKE_CLAUDE/agents" ]
}
