#!/usr/bin/env bats
# exec-guard-wiring.bats — TUNE-0519: verify datarim-exec-guard.sh is shipped in
# the framework and the 6 pipeline commands reference it as the hard floor.
# Usage: bats tests/exec-guard-wiring.bats

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

@test "guard script exists and is executable" {
    [ -f "$REPO_DIR/dev-tools/datarim-exec-guard.sh" ]
    [ -x "$REPO_DIR/dev-tools/datarim-exec-guard.sh" ]
}

@test "guard script references execution-host.sh library" {
    run grep -c "execution-host.sh" "$REPO_DIR/dev-tools/datarim-exec-guard.sh"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "guard script has PreToolUse stdin contract" {
    run grep -c "PreToolUse" "$REPO_DIR/dev-tools/datarim-exec-guard.sh"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "guard script emits permissionDecision deny JSON shape" {
    run grep -c "permissionDecision" "$REPO_DIR/dev-tools/datarim-exec-guard.sh"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "guard script handles unconfigured workspace (no binding -> silent exit 0)" {
    # The guard inherits fail-open behavior from execution-host.sh: when no
    # binding exists for the workspace, it exits 0 silently (no opinion).
    run grep -c "exit 0" "$REPO_DIR/dev-tools/datarim-exec-guard.sh"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# --- 6 pipeline commands reference the guard ---

@test "dr-prd references datarim-exec-guard.sh" {
    run grep -c "datarim-exec-guard.sh" "$REPO_DIR/commands/dr-prd.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-auto references datarim-exec-guard.sh" {
    run grep -c "datarim-exec-guard.sh" "$REPO_DIR/commands/dr-auto.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-archive references datarim-exec-guard.sh" {
    run grep -c "datarim-exec-guard.sh" "$REPO_DIR/commands/dr-archive.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-design references datarim-exec-guard.sh" {
    run grep -c "datarim-exec-guard.sh" "$REPO_DIR/commands/dr-design.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-compliance references datarim-exec-guard.sh" {
    run grep -c "datarim-exec-guard.sh" "$REPO_DIR/commands/dr-compliance.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "dr-quick references datarim-exec-guard.sh" {
    run grep -c "datarim-exec-guard.sh" "$REPO_DIR/commands/dr-quick.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# --- The execution-host shared library is present (guard depends on it) ---

@test "execution-host.sh library exists" {
    [ -f "$REPO_DIR/dev-tools/lib/execution-host.sh" ]
}
