#!/usr/bin/env bats
# Tests for dev-tools/datarim-exec-guard.sh + dev-tools/datarim-dispatch.sh (TUNE-0471)
# Usage: bats dev-tools/tests/datarim-exec-guard.bats
#
# Covers V-AC-1, V-AC-2, V-AC-3, V-AC-5, V-AC-8, V-AC-12.

GUARD="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/datarim-exec-guard.sh"

setup() {
    TEST_TMP="$(mktemp -d)"
    # Fake bound workspaces (with a datarim/ marker dir so walk-up resolves).
    ARCANADA_WS="$TEST_TMP/arcanada"
    AETHER_WS="$TEST_TMP/aether"
    UNBOUND_WS="$TEST_TMP/scratch-repo"
    mkdir -p "$ARCANADA_WS/datarim" "$ARCANADA_WS/Projects/Sub"
    mkdir -p "$AETHER_WS/datarim"
    mkdir -p "$UNBOUND_WS/datarim"
    # Audit log override (never write into ~/.claude/logs from tests).
    AUDIT_LOG="$TEST_TMP/exec-dispatch.log"

    # Test-only execution-hosts map (real IPs for arcanada/aether; unreachable
    # sentinel for the dispatch-refusal case).
    MAP="$TEST_TMP/execution-hosts.yml"
    cat > "$MAP" <<EOF
schema_version: 1
role: control
bindings:
  - workspace: $ARCANADA_WS
    space: arcanada
    required_host: arcana-devs
    host_aliases: [arcana-devs, Arcana-DEVS]
    tailscale_ip: "100.106.230.125"
    ssh_user: dev
    default_agent: claude-code
    allowed_agents: [claude-code, codex, cursor]
  - workspace: $AETHER_WS
    space: aether
    required_host: dev-ai
    host_aliases: [dev-ai]
    tailscale_ip: "100.118.134.82"
    ssh_user: aether
    default_agent: claude-code
    allowed_agents: [claude-code, codex, cursor]
EOF

    UNREACHABLE_MAP="$TEST_TMP/execution-hosts-unreachable.yml"
    cat > "$UNREACHABLE_MAP" <<EOF
schema_version: 1
role: control
bindings:
  - workspace: $ARCANADA_WS
    space: arcanada
    required_host: arcana-devs
    host_aliases: [arcana-devs, Arcana-DEVS]
    tailscale_ip: "100.127.255.254"
    ssh_user: dev
    default_agent: claude-code
    allowed_agents: [claude-code, codex, cursor]
EOF
}

teardown() {
    rm -rf "$TEST_TMP"
}

# --- fixture helper: PreToolUse Bash tool-call JSON ---
fixture_bash() {
    local cwd="$1" cmd="$2"
    jq -nc --arg cwd "$cwd" --arg cmd "$cmd" \
        '{hook_event_name: "PreToolUse", tool_name: "Bash", tool_input: {command: $cmd}, cwd: $cwd}'
}

# ---------------------------------------------------------------------------
# V-AC-1 / D-REQ-03: deny-arcanada
# ---------------------------------------------------------------------------
@test "deny-arcanada: executable /dr-* Bash call in bound Arcanada workspace denies with arcana-devs directive" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      fixture_bash '$ARCANADA_WS' 'claude /dr-do TUNE-9999' | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"permissionDecision"*"deny"* ]]
    [[ "$output" == *"arcana-devs"* ]]
    [[ "$output" == *"datarim-dispatch.sh"* ]]
}

# ---------------------------------------------------------------------------
# V-AC-2 / D-REQ-03, D-REQ-01: deny-aether
# ---------------------------------------------------------------------------
@test "deny-aether: executable /dr-* Bash call in bound Aether workspace denies with dev-ai directive" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      fixture_bash '$AETHER_WS' 'claude /dr-plan SPACE-1234' | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"permissionDecision"*"deny"* ]]
    [[ "$output" == *"dev-ai"* ]]
}

# ---------------------------------------------------------------------------
# V-AC-3 / D-REQ-06: unconfigured-silent
# ---------------------------------------------------------------------------
@test "unconfigured-silent: unbound workspace produces no opinion (empty stdout, exit 0)" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      fixture_bash '$UNBOUND_WS' 'claude /dr-do QCK-0001' | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# subdir-walk-up: cwd is a subdirectory of the bound workspace
# ---------------------------------------------------------------------------
@test "subdir-walk-up: cwd inside a subdirectory of bound workspace still denies" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      fixture_bash '$ARCANADA_WS/Projects/Sub' 'codex /dr-status TUNE-0001' | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"permissionDecision"*"deny"* ]]
    [[ "$output" == *"arcana-devs"* ]]
}

# ---------------------------------------------------------------------------
# override-marker: datarim/.exec-local-override allows + logs
# ---------------------------------------------------------------------------
@test "override-marker: presence of datarim/.exec-local-override allows and logs" {
    touch "$ARCANADA_WS/datarim/.exec-local-override"
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      fixture_bash '$ARCANADA_WS' 'claude /dr-do TUNE-9999' | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -f "$AUDIT_LOG" ]
    grep -q "override" "$AUDIT_LOG"
}

# ---------------------------------------------------------------------------
# doctor-exemption / V-AC-12: datarim-doctor.sh invocation allowed + audit-log
# ---------------------------------------------------------------------------
@test "doctor-exemption: datarim-doctor.sh invocation in bound workspace is allowed and logged" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      fixture_bash '$ARCANADA_WS' 'bash Projects/Datarim/code/datarim/scripts/datarim-doctor.sh --fix' | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -f "$AUDIT_LOG" ]
    grep -q "allowed-doctor-local" "$AUDIT_LOG"
}

# ---------------------------------------------------------------------------
# dispatch-not-blocked: guard must not deny its own dispatch channel
# ---------------------------------------------------------------------------
@test "dispatch-not-blocked: invoking datarim-dispatch.sh itself is not denied" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      fixture_bash '$ARCANADA_WS' 'dev-tools/datarim-dispatch.sh --workspace $ARCANADA_WS --task TUNE-9999' | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# non-executional Bash passes through silently (regression guard)
# ---------------------------------------------------------------------------
@test "non-executional Bash command in bound workspace passes through silently" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      fixture_bash '$ARCANADA_WS' 'ls -la' | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ===========================================================================
# Dispatch-dependent tests (V-AC-5, V-AC-8) — require datarim-dispatch.sh
# which ships separately. Skipped until the dispatch script lands in the
# framework repo alongside this guard (tracked as follow-up task).
# ===========================================================================

@test "vendor-default: dispatch without --agent resolves to claude-code (SKIPPED — needs dispatch)" {
    skip "datarim-dispatch.sh is not yet shipped in the framework repo"
}

@test "vendor-override: dispatch with --agent codex resolves to codex (SKIPPED — needs dispatch)" {
    skip "datarim-dispatch.sh is not yet shipped in the framework repo"
}

@test "invalid-vendor: dispatch with --agent foo is rejected (SKIPPED — needs dispatch)" {
    skip "datarim-dispatch.sh is not yet shipped in the framework repo"
}

@test "unreachable-host: dispatch to sentinel IP refuses with actionable message (SKIPPED — needs dispatch)" {
    skip "datarim-dispatch.sh is not yet shipped in the framework repo"
}

@test "invalid-task-id: dispatch rejects malformed task id (SKIPPED — needs dispatch)" {
    skip "datarim-dispatch.sh is not yet shipped in the framework repo"
}

# ===========================================================================
# DEF-1 (QA TUNE-0471): command-position matching, not substring matching.
# is_executional_command() must only match "claude"/"codex" (or /dr-*) at the
# START of the command or of a segment after |, ;, &&, || — never anywhere in
# the argument list (e.g. "rg claude ..." must NOT match).
# ===========================================================================

@test "DEF-1a: rg claude datarim/ in bound workspace passes through silently (not a false-deny)" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      fixture_bash '$ARCANADA_WS' 'rg claude datarim/' | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "DEF-1b: grep -r codex . in bound workspace passes through silently (not a false-deny)" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      fixture_bash '$ARCANADA_WS' 'grep -r codex .' | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "DEF-1c: claude /dr-do X at command start still denies" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      fixture_bash '$ARCANADA_WS' 'claude /dr-do TUNE-9999' | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"permissionDecision"*"deny"* ]]
}

@test "DEF-1d: cd foo && claude denies (claude at start of segment after &&)" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      fixture_bash '$ARCANADA_WS' 'cd foo && claude' | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"permissionDecision"*"deny"* ]]
}

@test "DEF-1e: VAR=1 claude denies (leading env-assignment tokens skipped)" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      fixture_bash '$ARCANADA_WS' 'VAR=1 claude' | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"permissionDecision"*"deny"* ]]
}

@test "DEF-1f: /opt/homebrew/bin/claude denies (match by basename of first token)" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      fixture_bash '$ARCANADA_WS' '/opt/homebrew/bin/claude' | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"permissionDecision"*"deny"* ]]
}

@test "DEF-1g: echo claude passes through silently (claude is an argument, not the command)" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      fixture_bash '$ARCANADA_WS' 'echo claude' | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ===========================================================================
# DEF-1h (QA TUNE-0474): heredoc-body false-positive. A Bash call that writes a
# document via a heredoc carries the document TEXT in .tool_input.command. A
# body line that BEGINS with /dr-<word> (or claude/codex) — e.g. a CTA snippet
# in a snapshot file — must NOT be treated as a command-position token. Live
# case: writing a /dr-auto snapshot whose body cited «/dr-archive» was denied.
# ===========================================================================

@test "DEF-1h: heredoc body line starting with /dr-do passes through (not a false-deny)" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      printf 'cat <<DOC\n/dr-do is the implementation stage.\nDOC' > '$BATS_TEST_TMPDIR/hd.txt'
      cmd=\"\$(cat '$BATS_TEST_TMPDIR/hd.txt')\"
      fixture_bash '$ARCANADA_WS' \"\$cmd\" | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "DEF-1i: heredoc body citing /dr-archive CTA passes through (real TUNE-0474 case)" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      printf 'cat > /tmp/snap.md <<EOF\nStep 6: /dr-archive TUNE-9999 to finalize.\nEOF' > '$BATS_TEST_TMPDIR/hd2.txt'
      cmd=\"\$(cat '$BATS_TEST_TMPDIR/hd2.txt')\"
      fixture_bash '$ARCANADA_WS' \"\$cmd\" | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "DEF-1j: quoted-delimiter heredoc body starting with claude passes through" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      printf \"cat <<'EOF'\nclaude runs the pipeline.\nEOF\" > '$BATS_TEST_TMPDIR/hd3.txt'
      cmd=\"\$(cat '$BATS_TEST_TMPDIR/hd3.txt')\"
      fixture_bash '$ARCANADA_WS' \"\$cmd\" | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "DEF-1k: real claude /dr-do AFTER a heredoc block still denies (strip must not eat the real command)" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      printf 'cat <<EOF\nsome text\nEOF\nclaude /dr-do TUNE-9999' > '$BATS_TEST_TMPDIR/hd4.txt'
      cmd=\"\$(cat '$BATS_TEST_TMPDIR/hd4.txt')\"
      fixture_bash '$ARCANADA_WS' \"\$cmd\" | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"permissionDecision"*"deny"* ]]
}

@test "DEF-1m: multi-line 'git commit -m' whose body line begins with /dr-archive passes through (TUNE-0486)" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      printf 'git commit -m \"TUNE-0474 fix\n\n/dr-archive was denied when committing; reworded.\"' > '$BATS_TEST_TMPDIR/m1.txt'
      cmd=\"\$(cat '$BATS_TEST_TMPDIR/m1.txt')\"
      fixture_bash '$ARCANADA_WS' \"\$cmd\" | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "DEF-1n: single-quoted multi-line commit message with codex body line passes through (TUNE-0486)" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      printf \"git commit -m 'wired codex fallback\ncodex path now works'\" > '$BATS_TEST_TMPDIR/m2.txt'
      cmd=\"\$(cat '$BATS_TEST_TMPDIR/m2.txt')\"
      fixture_bash '$ARCANADA_WS' \"\$cmd\" | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "DEF-1o: real 'claude /dr-do' chained AFTER a commit -m still denies (quote-strip must not eat the real command)" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      printf 'git commit -m \"msg body /dr-archive cited\" && claude /dr-do TUNE-9999' > '$BATS_TEST_TMPDIR/m3.txt'
      cmd=\"\$(cat '$BATS_TEST_TMPDIR/m3.txt')\"
      fixture_bash '$ARCANADA_WS' \"\$cmd\" | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"permissionDecision"*"deny"* ]]
}

@test "DEF-1p: escaped inner quote in a double-quoted message body does not break the strip (TUNE-0486)" {
    run bash -c "
      fixture_bash() { local cwd=\"\$1\" cmd=\"\$2\"; jq -nc --arg cwd \"\$cwd\" --arg cmd \"\$cmd\" '{hook_event_name: \"PreToolUse\", tool_name: \"Bash\", tool_input: {command: \$cmd}, cwd: \$cwd}'; }
      printf 'git commit -m \"note: agent said \\\\\"/dr-do\\\\\" here\"' > '$BATS_TEST_TMPDIR/m4.txt'
      cmd=\"\$(cat '$BATS_TEST_TMPDIR/m4.txt')\"
      fixture_bash '$ARCANADA_WS' \"\$cmd\" | DATARIM_EXEC_GUARD_MAP='$MAP' DATARIM_EXEC_GUARD_AUDIT_LOG='$AUDIT_LOG' bash '$GUARD'
    "
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
