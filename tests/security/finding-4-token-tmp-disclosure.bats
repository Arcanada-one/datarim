#!/usr/bin/env bats
# Origin: corporate audit 2026-04-28, Finding 4
# Severity: MEDIUM (OAuth token written world-readable to /tmp; venv on /tmp)
# Source: skills/utilities/ga4-admin.md
#
# Token storage was moved to XDG_STATE_HOME by SEC-0001 (commit 304cc25);
# this test guards against re-introduction and forces the venv off /tmp too.

setup() {
  REPO_ROOT="$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)"
  SKILL="$REPO_ROOT/skills/utilities/ga4-admin.md"
}

@test "Finding 4: skill does not store OAuth token under /tmp/" {
  ! grep -nE '/tmp/ga4-token' "$SKILL"
}

@test "Finding 4: skill does not place the venv under /tmp/" {
  ! grep -nE '/tmp/ga4-tools' "$SKILL"
}

@test "Finding 4: skill writes token via os.open(... 0o600 ...) atomically" {
  grep -qE 'os\.open\([^)]*0o600' "$SKILL"
  grep -qE 'O_EXCL' "$SKILL"
}

@test "Finding 4: skill creates state directory with mode 0o700" {
  grep -qE 'os\.makedirs\([^)]*0o700' "$SKILL"
}

@test "Finding 4: skill uses generic PROJECT_CREDS_DIR (not branded ARCANADA_CREDS_DIR)" {
  grep -qE 'PROJECT_CREDS_DIR' "$SKILL"
  ! grep -qE 'ARCANADA_CREDS_DIR' "$SKILL"
}
