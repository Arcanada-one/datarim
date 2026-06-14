#!/usr/bin/env bats
#
# Write-protected delegation gate + architecture-doc exemption.
#
# The PreToolUse guard denies the first Write of a documentation artefact
# (prd-*.md / plan-*.md / creative-*.md / *-task-description.md) to nudge the
# agent toward `coworker write`. The global delegation policy
# (~/.claude/CLAUDE.md § Coworker Delegation -> Do NOT delegate) EXEMPTS
# architectural decisions. The guard reconciles the two: a creative-doc whose
# basename matches an exempt glob (architecture / algorithm / design /
# threat-model / adr) is silently allowed (agent writes it directly). The
# exempt globs live in an external sibling file, fail-soft when absent.
#
# Cases mirror the task-description Validation Checklist V-1..V-8.

HOOK="${HOOK:-${BATS_TEST_DIRNAME}/../dev-tools/coworker-hook-guard.sh}"

setup() {
    [ -x "$HOOK" ] || skip "coworker-hook-guard not executable at $HOOK"
    command -v jq >/dev/null || skip "jq required"
    TMP_DOC_DIR=$(mktemp -d "${BATS_TMPDIR:-/tmp}/dr-do-wp.XXXXXX")
}

teardown() {
    [ -n "${TMP_DOC_DIR:-}" ] && rm -rf "$TMP_DOC_DIR"
}

# Invoke the hook with a PreToolUse Write payload for file_path $1.
# Optional $2 overrides COWORKER_GUARD_EXEMPT_FILE (allowlist path).
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

# --- V-2 (AC-2): non-architecture creative-doc still denied ----------------
@test "V-2 non-architecture creative-doc -> deny (delegation preserved)" {
    run run_hook_write "$TMP_DOC_DIR/creative-database-schema.md"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}

# --- V-1 (AC-1): architecture creative-doc -> silent allow ------------------
@test "V-1 architecture creative-doc -> silent allow (write directly)" {
    run run_hook_write "$TMP_DOC_DIR/creative-DEV-1462-self-healing-reviewer-architecture.md"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "V-1b algorithm creative-doc -> silent allow" {
    run run_hook_write "$TMP_DOC_DIR/creative-algorithm-design-uuid48.md"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "V-1c threat-model creative-doc -> silent allow" {
    run run_hook_write "$TMP_DOC_DIR/creative-auth-threat-model.md"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- V-5 (AC-5): case-insensitive match ------------------------------------
@test "V-5 case-insensitive: Creative-...-Architecture.md -> silent allow" {
    run run_hook_write "$TMP_DOC_DIR/Creative-API-Architecture-uuid48.md"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- V-3 (AC-3): fail-soft when allowlist absent ---------------------------
@test "V-3 allowlist absent -> architecture doc denied (fail-soft to gate)" {
    run run_hook_write "$TMP_DOC_DIR/creative-DEV-1462-architecture.md" "$TMP_DOC_DIR/does-not-exist.patterns"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}

# --- V-4 (AC-4): deny reason carries the escape-hatch ----------------------
@test "V-4 deny reason names the exempt-allowlist escape-hatch" {
    run run_hook_write "$TMP_DOC_DIR/creative-database-schema.md"
    [ "$status" -eq 0 ]
    reason=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')
    case "$reason" in
        *coworker-delegation-exempt.patterns*) : ;;
        *) printf 'reason missing escape-hatch: %s\n' "$reason" >&2; return 1 ;;
    esac
}

# --- No-regression: other protected artefacts still denied -----------------
@test "no-regression: prd-*.md still denied" {
    run run_hook_write "$TMP_DOC_DIR/prd-FOO-0001.md"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}

@test "no-regression: *-task-description.md still denied" {
    run run_hook_write "$TMP_DOC_DIR/FOO-0001-task-description.md"
    [ "$status" -eq 0 ]
    decision=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')
    [ "$decision" = "deny" ]
}

# --- Custom per-project allowlist via env override -------------------------
@test "AC-3 custom allowlist file via COWORKER_GUARD_EXEMPT_FILE" {
    custom="$TMP_DOC_DIR/custom.patterns"
    printf '%s\n' '# custom' 'creative-*-myteam-spec.md' > "$custom"
    run run_hook_write "$TMP_DOC_DIR/creative-billing-myteam-spec.md" "$custom"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
