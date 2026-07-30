#!/usr/bin/env bats
#
# Voice-bearing content gate — coworker-hook-guard MUST ALLOW native Write
# to voice-bearing paths and MUST DENY coworker write to the same paths.
#
# Voice-bearing = content where the assigned model writes it itself, never
# via coworker: published articles, social posts, ecosystem-site docs,
# consilium / panel reasoning.
#
# The hook's check_write_protected() currently has the OPPOSITE behaviour:
# it DENIES native Write to */wiki/* and */Social\ Media/* and demands
# delegation. This file asserts the correct behaviour.
#
# Cases follow the TUNE-0537 brief deliverables 1-3.

HOOK="${HOOK:-${BATS_TEST_DIRNAME}/../dev-tools/coworker-hook-guard.sh}"

setup() {
    [ -x "$HOOK" ] || skip "coworker-hook-guard not executable at $HOOK"
    command -v jq >/dev/null || skip "jq required"
    TMP_DIR=$(mktemp -d "${BATS_TMPDIR:-/tmp}/dr-vb-guard.XXXXXX")
    mkdir -p "$TMP_DIR/Social Media/Мои посты/Telegram"
    mkdir -p "$TMP_DIR/wiki/_raw_"
    mkdir -p "$TMP_DIR/wiki/some-project"
    # doc-artefact dir for no-regression tests
    mkdir -p "$TMP_DIR/docs"
}

teardown() {
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
}

# Invoke the hook with a PreToolUse Write payload for file_path $1.
# Optional COWORKER_GUARD_EXEMPT_FILE as $2.
run_hook_write() {
    local fp="$1" exempt="${2:-}"
    local payload
    payload=$(jq -nc --arg f "$fp" '{
        hook_event_name: "PreToolUse",
        tool_name: "Write",
        tool_input: { file_path: $f }
    }')
    if [ -n "$exempt" ]; then
        printf '%s' "$payload" | COWORKER_GUARD_EXEMPT_FILE="$exempt" "$HOOK"
    else
        printf '%s' "$payload" | "$HOOK"
    fi
}

# Invoke the hook with a PreToolUse Bash payload for command $1.
run_hook_bash() {
    local cmd="$1"
    local payload
    payload=$(jq -nc --arg c "$cmd" '{
        hook_event_name: "PreToolUse",
        tool_name: "Bash",
        tool_input: { command: $c }
    }')
    printf '%s' "$payload" | "$HOOK"
}

# --- V-1: native Write to Social Media/ path ALLOWED --------------------------
@test "V-1 native Write to Social Media/ path ALLOWED" {
    local fp="$TMP_DIR/Social Media/Мои посты/Telegram/test-post.md"
    run run_hook_write "$fp"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- V-2: native Write to wiki/ path ALLOWED ----------------------------------
@test "V-2 native Write to wiki/ path ALLOWED" {
    local fp="$TMP_DIR/wiki/some-project/page.md"
    run run_hook_write "$fp"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- V-3: coworker write --target voice-bearing path DENIED -------------------
@test "V-3 coworker write --target voice-bearing path DENIED" {
    local fp="$TMP_DIR/Social Media/Мои посты/Telegram/test-post.md"
    local cmd="coworker write --profile datarim-write --spec \"write a post\" --target \"$fp\""
    run run_hook_bash "$cmd"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
    reason=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')
    case "$reason" in
        *"voice-bearing"*|*"Voice-bearing"*) : ;;
        *) printf 'deny reason missing voice-bearing: %s\n' "$reason" >&2; return 1 ;;
    esac
}

# --- V-4: coworker ask over source material ALLOWED (bulk read, not voice generation)
@test "V-4 coworker ask over source material ALLOWED (bulk read)" {
    local cmd="coworker ask --paths \"$TMP_DIR/wiki/_raw_/data.md\" --question \"summarize this\""
    run run_hook_bash "$cmd"
    [ "$status" -eq 0 ]
    # Should be empty (passthrough) — not a deny
    [ -z "$output" ]
}

# --- V-5: prd-*.md still DENIED (no regression) -------------------------------
@test "V-5 no-regression: prd-*.md still DENIED for native Write" {
    local fp="$TMP_DIR/docs/prd-FOO-0001.md"
    run run_hook_write "$fp"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}

# --- V-6: coworker write to prd-*.md ALLOWED (non-voice-bearing doc delegation is fine)
@test "V-6 coworker write to prd-*.md ALLOWED (doc delegation is fine)" {
    local fp="$TMP_DIR/docs/prd-FOO-0001.md"
    local cmd="coworker write --profile datarim-write --spec \"draft PRD\" --target \"$fp\""
    run run_hook_bash "$cmd"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- V-7: .no-coworker marker: native Write ALLOWED ---------------------------
@test "V-7 .no-coworker marker: native Write ALLOWED (all delegation nudging off)" {
    # Create a fake datarim/ with .no-coworker marker
    mkdir -p "$TMP_DIR/project/datarim"
    touch "$TMP_DIR/project/datarim/.no-coworker"
    # Write target is a prd-*.md which would normally be denied
    local fp="$TMP_DIR/project/docs/prd-FOO-0001.md"
    mkdir -p "$(dirname "$fp")"
    run run_hook_write "$fp"
    [ "$status" -eq 0 ]
    # In .no-coworker zone, even doc artifacts pass through
    [ -z "$output" ]
}

# --- V-8: .no-coworker marker: coworker write DENIED --------------------------
@test "V-8 .no-coworker marker: coworker write DENIED (any target)" {
    mkdir -p "$TMP_DIR/project/datarim"
    touch "$TMP_DIR/project/datarim/.no-coworker"
    local fp="$TMP_DIR/project/docs/prd-FOO-0001.md"
    mkdir -p "$(dirname "$fp")"
    local cmd="coworker write --profile datarim-write --spec \"draft\" --target \"$fp\""
    run run_hook_bash "$cmd"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}

# --- V-9: .no-coworker marker: coworker ask DENIED ----------------------------
@test "V-9 .no-coworker marker: coworker ask DENIED" {
    mkdir -p "$TMP_DIR/project/datarim"
    touch "$TMP_DIR/project/datarim/.no-coworker"
    local fp="$TMP_DIR/project/docs/some-doc.md"
    local cmd="coworker ask --paths \"$fp\" --question \"summarize\""
    run run_hook_bash "$cmd"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}

# --- V-10: fail-soft — missing datarim/ → passthrough -------------------------
@test "V-10 fail-soft: missing datarim/ — Write passthrough" {
    # Write to a path under $TMP_DIR where no datarim/ exists (setup only creates
    # Social Media/ and wiki/ subdirs, not a datarim/)
    local fp="$TMP_DIR/docs/non-datarim-project.md"
    mkdir -p "$(dirname "$fp")"
    run run_hook_write "$fp"
    [ "$status" -eq 0 ]
    # Should passthrough (no deny) since there's no datarim/ context
    [ -z "$output" ]
}

# --- V-11: fail-soft — hook error → exit 0 (no deny) --------------------------
@test "V-11 fail-soft: hook internal error → exits 0 (no deny, no crash)" {
    # Trigger a Bash path with a malformed coworker write that the parser
    # handles gracefully (empty --target)
    local cmd="coworker write --profile datarim-write --spec \"test\""
    run run_hook_bash "$cmd"
    [ "$status" -eq 0 ]
    # Should passthrough (no target → can't determine voice-bearing → allow)
    [ -z "$output" ]
}

# --- V-12: native Write to existing Social Media/ file ALLOWED (not first draft)
@test "V-12 native Write to existing Social Media/ file ALLOWED (existing file)" {
    local fp="$TMP_DIR/Social Media/Мои посты/Telegram/existing-post.md"
    touch "$fp"
    run run_hook_write "$fp"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- V-13: coworker ask with generation keywords → DENIED ----------------------
@test "V-13 coworker ask with generation keywords → DENIED (voice-bearing heuristic)" {
    local cmd="coworker ask --profile datarim-write --question \"write a draft article about AI\""
    run run_hook_bash "$cmd"
    [ "$status" -eq 0 ]
    # Heuristic: generation keyword "write" in --question → deny
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}
