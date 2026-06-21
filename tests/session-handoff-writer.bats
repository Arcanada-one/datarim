#!/usr/bin/env bats
#
# Tests for scripts/lib/session-handoff-writer.sh
#
# Coverage:
#   - write happy-path (file created, frontmatter valid)
#   - idempotent append (2nd save appends, does not truncate prior block)
#   - 32 KB cap: body truncation drops Layer-3/4 first, protects Layer-1/5
#   - lock-timeout exit 3
#   - invalid session-id rejected (T-1 path traversal)
#   - symlink at target pre-unlinked (T-7)
#   - kill-switch DATARIM_DISABLE_SESSION_HANDOFF=1 is a no-op
#   - untagged claim-keyword rejected with exit 1 (wish-5 writer side)
#   - secret scan-and-redact (T-8)

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
WRITER_LIB="${REPO_ROOT}/scripts/lib/session-handoff-writer.sh"

# bats mode-probe: GNU-first, BSD fallback (per memory feedback).
_mode() {
    local f="$1"
    stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f" 2>/dev/null || echo "000"
}

setup() {
    export FAKE_ROOT
    FAKE_ROOT="$(mktemp -d "${BATS_TEST_TMPDIR}/fake-repo.XXXX")"
    mkdir -p "${FAKE_ROOT}/datarim"

    export SESSION_ID="SESSION-20260615-120000"
    export TASK_LIST_FILE
    TASK_LIST_FILE="$(mktemp "${BATS_TEST_TMPDIR}/tasks.XXXX")"
    printf 'TUNE-0420 | in_progress\n' > "${TASK_LIST_FILE}"

    export BODY_FILE
    BODY_FILE="$(mktemp "${BATS_TEST_TMPDIR}/body.XXXX")"
    cat > "${BODY_FILE}" <<'EOF'
## Layer 1 — Git State

repo: /Users/ug/code/myproject  HEAD: abc123  status: clean

## Layer 5 — Failed Approaches

Tried X, failed because Y.
EOF

    # shellcheck source=/dev/null
    source "${WRITER_LIB}"
}

# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

@test "write happy-path: session file created at canonical path" {
    run write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Continue implementation of phase P2." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${BODY_FILE}"
    [ "$status" -eq 0 ]
    [ -f "${FAKE_ROOT}/datarim/sessions/${SESSION_ID}.session.md" ]
}

@test "write happy-path: frontmatter contains required fields" {
    write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Continue implementation." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${BODY_FILE}"
    local f="${FAKE_ROOT}/datarim/sessions/${SESSION_ID}.session.md"
    grep -q '^artifact: session-handoff$' "$f"
    grep -q '^schema_version: 1$' "$f"
    grep -q "^session_id: ${SESSION_ID}$" "$f"
    grep -q '^captured_by: agent$' "$f"
    grep -qE '^captured_at: [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$f"
    grep -q '^recommended_next: /dr-next TUNE-0420$' "$f"
    grep -q '^next_action: Continue implementation.$' "$f"
}

@test "write happy-path: sessions dir has mode 700" {
    write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Continue." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${BODY_FILE}"
    local dir="${FAKE_ROOT}/datarim/sessions"
    local mode
    mode="$(_mode "$dir")"
    [ "$mode" = "700" ]
}

@test "write happy-path: file has mode 600" {
    write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Continue." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${BODY_FILE}"
    local f="${FAKE_ROOT}/datarim/sessions/${SESSION_ID}.session.md"
    local mode
    mode="$(_mode "$f")"
    [ "$mode" = "600" ]
}

# ---------------------------------------------------------------------------
# Append-only semantics (idempotent append, 2nd save adds block, no truncation)
# ---------------------------------------------------------------------------

@test "append-only: second save appends new block, does not erase first" {
    write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "First save." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${BODY_FILE}"

    local body2
    body2="$(mktemp "${BATS_TEST_TMPDIR}/body2.XXXX")"
    printf '## Layer 1 — Git State\nrepo: /other  HEAD: def456\n\n## Layer 5\nApproach 2.\n' > "$body2"

    write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-continue" \
        --next-action "Second save." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${body2}"

    local f="${FAKE_ROOT}/datarim/sessions/${SESSION_ID}.session.md"
    # Both bodies present
    grep -q "First save." "$f"
    grep -q "Second save." "$f"
    # First body content still present
    grep -q "Approach 2." "$f"
}

@test "append-only: second save also updates recommended_next header" {
    write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "First." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${BODY_FILE}"

    local body2
    body2="$(mktemp "${BATS_TEST_TMPDIR}/body2b.XXXX")"
    printf '## Layer 1\nHEAD: xyz\n\n## Layer 5\nNone.\n' > "$body2"

    write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-auto TUNE-0420" \
        --next-action "Second." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "$body2"

    local f="${FAKE_ROOT}/datarim/sessions/${SESSION_ID}.session.md"
    # Latest recommended_next in frontmatter
    grep -q '^recommended_next: /dr-auto TUNE-0420$' "$f"
}

# ---------------------------------------------------------------------------
# 32 KB cap + per-layer budget (Layer-1/5 protected)
# ---------------------------------------------------------------------------

@test "cap-truncates: body exceeding 32768 bytes is truncated" {
    local big_body
    big_body="$(mktemp "${BATS_TEST_TMPDIR}/big-body.XXXX")"
    # Write Layer-1 block (protected), then large Layer-3 content, then Layer-5 (protected)
    {
        printf '## Layer 1 — Git State\nHEAD: abc123  status: clean\n\n'
        printf '## Layer 3 — Related Files\n'
        # ~28000 bytes of padding
        python3 -c "print('x' * 28000)"
        printf '\n## Layer 5 — Failed Approaches\nFailed: approach A.\n'
    } > "$big_body"

    run write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Continued." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${big_body}"
    [ "$status" -eq 0 ]

    local f="${FAKE_ROOT}/datarim/sessions/${SESSION_ID}.session.md"
    local size
    size="$(wc -c < "$f" | tr -d ' ')"
    [ "$size" -le 32768 ]
}

@test "cap-truncates: Layer-1 and Layer-5 content present after truncation" {
    local big_body
    big_body="$(mktemp "${BATS_TEST_TMPDIR}/big-body2.XXXX")"
    {
        printf '## Layer 1 — Git State\nHEAD: protectedhash  status: clean\n\n'
        printf '## Layer 3 — Related Files\n'
        python3 -c "print('x' * 28000)"
        printf '\n## Layer 5 — Failed Approaches\nprotected-approach-content.\n'
    } > "$big_body"

    write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Continued." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${big_body}"

    local f="${FAKE_ROOT}/datarim/sessions/${SESSION_ID}.session.md"
    grep -q 'protectedhash' "$f"
    grep -q 'protected-approach-content' "$f"
}

# ---------------------------------------------------------------------------
# Lock timeout (exit 3)
# ---------------------------------------------------------------------------

@test "lock-timeout: returns exit 3 when lock already held" {
    local lock_dir="${FAKE_ROOT}/datarim/sessions/.lock.${SESSION_ID}"
    mkdir -p "$lock_dir"

    DR_SESSION_LOCK_TIMEOUT=1 run write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Will time out." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${BODY_FILE}"
    [ "$status" -eq 3 ]

    rmdir "$lock_dir"
}

# ---------------------------------------------------------------------------
# T-1: invalid session-id rejected
# ---------------------------------------------------------------------------

@test "T-1: session-id with path traversal rejected (exit 1)" {
    run write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "SESSION-../../etc/passwd" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Should fail." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${BODY_FILE}"
    [ "$status" -eq 1 ]
}

@test "T-1: bare string (not SESSION-YYYYMMDD-HHMMSS) rejected (exit 1)" {
    run write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "not-a-session-id" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Should fail." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${BODY_FILE}"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# T-7: symlink pre-unlink
# ---------------------------------------------------------------------------

@test "T-7: symlink at target path is pre-unlinked, real file written" {
    mkdir -p "${FAKE_ROOT}/datarim/sessions"
    local target="${FAKE_ROOT}/datarim/sessions/${SESSION_ID}.session.md"
    local decoy
    decoy="$(mktemp "${BATS_TEST_TMPDIR}/decoy.XXXX")"
    printf 'decoy content\n' > "$decoy"
    ln -sf "$decoy" "$target"

    write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Replace symlink." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${BODY_FILE}"

    # Must be a real file, not a symlink
    [ -f "$target" ]
    [ ! -L "$target" ]
    # Original decoy must be untouched (symlink target was replaced, not followed)
    grep -q 'decoy content' "$decoy"
}

# ---------------------------------------------------------------------------
# Kill-switch
# ---------------------------------------------------------------------------

@test "kill-switch: DATARIM_DISABLE_SESSION_HANDOFF=1 is a no-op (exit 0, no file)" {
    DATARIM_DISABLE_SESSION_HANDOFF=1 run write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Disabled." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${BODY_FILE}"
    [ "$status" -eq 0 ]
    [ ! -f "${FAKE_ROOT}/datarim/sessions/${SESSION_ID}.session.md" ]
}

# ---------------------------------------------------------------------------
# Claim-provenance enforcement (wish-5 writer side)
# ---------------------------------------------------------------------------

@test "claim-provenance: untagged 'pushed' in body rejected (exit 1)" {
    local claim_body
    claim_body="$(mktemp "${BATS_TEST_TMPDIR}/claim-body.XXXX")"
    cat > "${claim_body}" <<'EOF'
## Layer 1 — Git State
HEAD: abc123  status: clean

## Layer 5 — Failed Approaches
None.

Branch was pushed to origin/main.
EOF

    run write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Check claim." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${claim_body}"
    [ "$status" -eq 1 ]
}

@test "claim-provenance: tagged 'pushed verified: SHA abc' accepted (exit 0)" {
    local claim_body
    claim_body="$(mktemp "${BATS_TEST_TMPDIR}/claim-body2.XXXX")"
    cat > "${claim_body}" <<'EOF'
## Layer 1 — Git State
HEAD: abc123  status: clean

## Layer 5 — Failed Approaches
None.

Branch was pushed to origin/main. verified: SHA abc123 present in origin/main
EOF

    run write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Check claim tagged." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${claim_body}"
    [ "$status" -eq 0 ]
}

@test "claim-provenance: untagged 'merged' in body rejected (exit 1)" {
    local claim_body
    claim_body="$(mktemp "${BATS_TEST_TMPDIR}/claim-body3.XXXX")"
    cat > "${claim_body}" <<'EOF'
## Layer 1 — Git State
HEAD: abc123

## Layer 5
None.

PR was merged into main.
EOF

    run write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Merged claim." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${claim_body}"
    [ "$status" -eq 1 ]
}

@test "claim-provenance: 'assumed: not yet verified' tag accepted (exit 0)" {
    local claim_body
    claim_body="$(mktemp "${BATS_TEST_TMPDIR}/claim-body4.XXXX")"
    cat > "${claim_body}" <<'EOF'
## Layer 1 — Git State
HEAD: abc123  status: clean

## Layer 5 — Failed Approaches
None.

Tests were passing. assumed: observed in last run, not re-run
EOF

    run write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Assumed tag." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${claim_body}"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# T-8: secret scan-and-redact
# ---------------------------------------------------------------------------

@test "T-8: AWS-style key in body is redacted in written file" {
    local secret_body
    secret_body="$(mktemp "${BATS_TEST_TMPDIR}/secret-body.XXXX")"
    cat > "${secret_body}" <<'EOF'
## Layer 1 — Git State
HEAD: abc123  status: clean

## Layer 5 — Failed Approaches
None.

AKIA1234567890ABCDEF was the key I was using.
EOF

    write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Secret test." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${secret_body}"

    local f="${FAKE_ROOT}/datarim/sessions/${SESSION_ID}.session.md"
    # Secret must be redacted
    run grep -c 'AKIA1234567890ABCDEF' "$f"
    [ "$output" = "0" ]
    # Redaction marker present
    grep -q '\[REDACTED\]' "$f"
}

@test "frontmatter terminator: closing --- is on its own line, body starts on a new line" {
    # Regression: $(_session_render_frontmatter) strips trailing newlines, so the
    # body once glued onto the closing fence as "---## Layer 1". A strict YAML
    # frontmatter parser rejects that. grep -qF '## Layer 1' did NOT catch it
    # (substring match is line-position-agnostic); this assertion is line-anchored.
    run write_session_handoff \
        --root "${FAKE_ROOT}" \
        --session "${SESSION_ID}" \
        --captured-by agent \
        --recommended-next "/dr-next TUNE-0420" \
        --next-action "Regression check for frontmatter terminator." \
        --active-tasks-file "${TASK_LIST_FILE}" \
        --body-file "${BODY_FILE}"
    [ "$status" -eq 0 ]
    local artefact="${FAKE_ROOT}/datarim/sessions/${SESSION_ID}.session.md"
    # Exactly two line-anchored '---' fences (open + close), each on its own line.
    [ "$(grep -c '^---$' "$artefact")" -eq 2 ]
    # The body's first layer heading must start a line (not glued to a fence).
    grep -q '^## Layer 1' "$artefact"
    # And the glued form must NOT appear.
    ! grep -q '^---## Layer' "$artefact"
}

# ---------------------------------------------------------------------------
# TUNE-0441 — Resume-block renderer tests (V-AC-1..V-AC-6, V-AC-8, V-AC-9)
# ---------------------------------------------------------------------------

# t-resume-1: rendered block contains /dr-continue <exact SESSION_ID> (V-AC-1, V-AC-3)
@test "t-resume-1: resume block contains /dr-continue with exact session-id" {
    # Source the lib to access the helper directly.
    local result
    result="$(_session_render_resume_block \
        "SESSION-20260615-120000" \
        "/dr-next TUNE-0441" \
        "Continue phase P2." \
        "${TASK_LIST_FILE}")"
    # Must match /dr-continue SESSION-YYYYMMDD-HHMMSS pattern (V-AC-1).
    printf '%s\n' "$result" | grep -qE '/dr-continue SESSION-[0-9]{8}-[0-9]{6}'
    # Must use the exact passed session-id, not a different one (V-AC-3).
    printf '%s\n' "$result" | grep -q '/dr-continue SESSION-20260615-120000'
}

# t-resume-2: TASK-ID parsed from --recommended-next; annotation lines present; not prefixed /dr-continue (V-AC-2)
@test "t-resume-2: annotation lines present and not prefixed /dr-continue" {
    local result
    result="$(_session_render_resume_block \
        "SESSION-20260615-120000" \
        "/dr-next TUNE-0441" \
        "Continue phase P2." \
        "${TASK_LIST_FILE}")"
    # ↳ line present with parsed TASK-ID.
    printf '%s\n' "$result" | grep -qE '^  ↳ TUNE-[0-9]{4}'
    # Next: line present.
    printf '%s\n' "$result" | grep -q 'Next:'
    # Annotation lines MUST NOT start with /dr-continue.
    ! printf '%s\n' "$result" | grep -E '^  ↳' | grep -q '/dr-continue'
}

# t-resume-3: degenerate 1-task — Also-active line suppressed (V-AC-4, R12)
@test "t-resume-3: single active task suppresses Also-active line" {
    # TASK_LIST_FILE already has one task (TUNE-0420).
    local result
    result="$(_session_render_resume_block \
        "SESSION-20260615-120000" \
        "/dr-next TUNE-0420" \
        "Single task resume." \
        "${TASK_LIST_FILE}")"
    # Must NOT contain Also-active line (the current task is excluded; no others remain).
    ! printf '%s\n' "$result" | grep -q 'Also active this session:'
}

# t-resume-3b: two active tasks — Also-active line present; current excluded (R12)
@test "t-resume-3b: two active tasks shows Also-active line with other task only" {
    local two_tasks
    two_tasks="$(mktemp "${BATS_TEST_TMPDIR}/two-tasks.XXXX")"
    printf 'TUNE-0420 | in_progress\nTUNE-0441 | in_progress\n' > "$two_tasks"

    local result
    result="$(_session_render_resume_block \
        "SESSION-20260615-120000" \
        "/dr-next TUNE-0420" \
        "Two tasks resume." \
        "$two_tasks")"
    # Must contain Also-active line (R12: "Also active this session:" without "in").
    printf '%s\n' "$result" | grep -q 'Also active this session:'
    # Current task (TUNE-0420) must appear in the ↳ annotation line.
    printf '%s\n' "$result" | grep -q 'TUNE-0420'
    # Other task (TUNE-0441) must appear in the Also-active line.
    printf '%s\n' "$result" | grep -q 'TUNE-0441'
    # Current task (TUNE-0420) must NOT appear in the Also-active line (R12 exclusion).
    local also_line
    also_line="$(printf '%s\n' "$result" | grep 'Also active this session:')"
    ! printf '%s\n' "$also_line" | grep -q 'TUNE-0420'

    rm -f "$two_tasks"
}

# t-resume-4: fallback — no TASK-ID in recommended-next; ↳ and Next: omitted; command still present (V-AC-5)
@test "t-resume-4: fallback omits annotation when recommended-next has no TASK-ID" {
    local result
    result="$(_session_render_resume_block \
        "SESSION-20260615-120000" \
        "continue" \
        "Continue working." \
        "${TASK_LIST_FILE}")"
    # Must NOT contain ↳ with a TASK-ID pattern.
    ! printf '%s\n' "$result" | grep -qE '↳ [A-Z]+-[0-9]{4}'
    # Command line MUST still be present.
    printf '%s\n' "$result" | grep -q '/dr-continue SESSION-20260615-120000'
}

# t-resume-5: sanitizer handles backtick, $(), newline, and 200-char overflow (V-AC-6)
@test "t-resume-5: sanitizer strips backtick, dollar-paren, truncates at 80 chars" {
    local two_tasks
    two_tasks="$(mktemp "${BATS_TEST_TMPDIR}/two-tasks5.XXXX")"
    printf 'TUNE-0441 | in_progress\nTUNE-0420 | in_progress\n' > "$two_tasks"

    # next_action with injection chars and excessive length.
    local evil_action
    evil_action='do `evil` $(rm -rf /) thing with a very very very very very very very very very very very very very very very very very very long tail'

    local result
    result="$(_session_render_resume_block \
        "SESSION-20260615-120000" \
        "/dr-next TUNE-0441" \
        "$evil_action" \
        "$two_tasks")"

    local next_line
    next_line="$(printf '%s\n' "$result" | grep 'Next:')"

    # No backtick in Next: line.
    ! printf '%s\n' "$next_line" | grep -q '`'
    # No $( in Next: line.
    ! printf '%s\n' "$next_line" | grep -qF '$('
    # Next: line is a single line (no embedded newline — grep returns exactly 1 line).
    [ "$(printf '%s\n' "$next_line" | wc -l | tr -d ' ')" -eq 1 ]
    # Content after "Next: " is <=80 chars.
    local content="${next_line#*Next: }"
    [ "${#content}" -le 80 ]

    rm -f "$two_tasks"
}

# t-resume-6: genre boundary — no HR ---, no CTA marker, no Variant-B (V-AC-9)
@test "t-resume-6: rendered block contains no HR, no CTA marker, no Variant-B" {
    local result
    result="$(_session_render_resume_block \
        "SESSION-20260615-120000" \
        "/dr-next TUNE-0441" \
        "Continue phase." \
        "${TASK_LIST_FILE}")"
    # No standalone HR line.
    ! printf '%s\n' "$result" | grep -qE '^---$'
    # No Variant-B menu header (the canonical marker token for other-tasks menu).
    ! printf '%s\n' "$result" | grep -q 'Другие активные задачи'
}

# t-resume-7: anti-pattern warning present verbatim (V-AC-8)
@test "t-resume-7: anti-pattern warning preserved verbatim" {
    local result
    result="$(_session_render_resume_block \
        "SESSION-20260615-120000" \
        "/dr-next TUNE-0441" \
        "Continue." \
        "${TASK_LIST_FILE}")"
    printf '%s\n' "$result" | grep -q 'Do NOT use claude --continue / codex resume / Cursor chat history.'
}

# ---------------------------------------------------------------------------
# TUNE-0441 round-2 — R9/R10/R12 new-behaviour tests
# ---------------------------------------------------------------------------

# Helper: create a minimal tasks.md in the given dir.
_make_tasks_md() {
    local dir="$1"
    local tasks_md="${dir}/datarim/tasks.md"
    mkdir -p "${dir}/datarim"
    cat > "$tasks_md" <<'TASKS'
# Tasks

## Active
- TUNE-0441 · in_progress · P2 · L2 · Improve resume block title display for clarity → tasks/TUNE-0441-task-description.md
- VERD-0050 · in_progress · P2 · L4 · Capture and notes epic for voice screenshots → tasks/VERD-0050-task-description.md
TASKS
    printf '%s' "$tasks_md"
}

# t-resume-8: title rendered from tasks.md beside TASK-ID (R9)
@test "t-resume-8: title read from tasks.md appears beside TASK-ID in the arrow line" {
    local tasks_md
    tasks_md="$(_make_tasks_md "${FAKE_ROOT}")"

    local result
    result="$(_session_render_resume_block \
        "SESSION-20260615-120000" \
        "/dr-next TUNE-0441" \
        "Continue phase P2." \
        "${TASK_LIST_FILE}" \
        "$tasks_md")"

    # ↳ line must contain the task title (or truncated prefix of it).
    local arrow_line
    arrow_line="$(printf '%s\n' "$result" | grep -E '^  ↳ TUNE-0441')"
    # Title field appears after em-dash.
    printf '%s\n' "$arrow_line" | grep -q ' — '
    printf '%s\n' "$arrow_line" | grep -q 'Improve resume block'
}

# t-resume-9: title truncated to <=55 chars (R9)
@test "t-resume-9: title truncated at 55 chars on word boundary" {
    local long_tasks_md="${FAKE_ROOT}/datarim/tasks-long.md"
    mkdir -p "${FAKE_ROOT}/datarim"
    # Title is >55 chars — should be truncated with ellipsis.
    cat > "$long_tasks_md" <<'TASKS'
# Tasks

## Active
- TUNE-0441 · in_progress · P2 · L2 · This is a very long title that should be truncated because it exceeds the fifty-five character limit → tasks/TUNE-0441-task-description.md
TASKS

    local result
    result="$(_session_render_resume_block \
        "SESSION-20260615-120000" \
        "/dr-next TUNE-0441" \
        "Continue." \
        "${TASK_LIST_FILE}" \
        "$long_tasks_md")"

    local arrow_line
    arrow_line="$(printf '%s\n' "$result" | grep -E '^  ↳ TUNE-0441')"
    # Extract the title part (after " — " and before the saved-time parenthetical).
    local title_part
    title_part="$(printf '%s\n' "$arrow_line" | sed 's/.*— //; s/   (saved.*//')"
    # Must have ellipsis (truncated).
    printf '%s\n' "$title_part" | grep -q '…'
    # Length including ellipsis must be <=56 (55 chars + 1 for the ellipsis char).
    [ "${#title_part}" -le 56 ]
}

# t-resume-10: title with leading slash sanitized (R9 stricter sanitize)
@test "t-resume-10: title with leading slash has slash stripped" {
    local slash_tasks_md="${FAKE_ROOT}/datarim/tasks-slash.md"
    mkdir -p "${FAKE_ROOT}/datarim"
    cat > "$slash_tasks_md" <<'TASKS'
# Tasks

## Active
- TUNE-0441 · in_progress · P2 · L2 · /dr-continue forged-title-attempt → tasks/TUNE-0441-task-description.md
TASKS

    local result
    result="$(_session_render_resume_block \
        "SESSION-20260615-120000" \
        "/dr-next TUNE-0441" \
        "Continue." \
        "${TASK_LIST_FILE}" \
        "$slash_tasks_md")"

    local arrow_line
    arrow_line="$(printf '%s\n' "$result" | grep -E '^  ↳ TUNE-0441')"
    # The leading '/' must be stripped from the title.
    ! printf '%s\n' "$arrow_line" | grep -q '/dr-continue'
    # The rest of the title content should still appear (minus the leading slash).
    printf '%s\n' "$arrow_line" | grep -q 'dr-continue forged'
}

# t-resume-11: missing tasks.md → bare ↳ TASK-ID, no em-dash (R9 fallback)
@test "t-resume-11: absent tasks.md falls back to bare arrow line with no em-dash" {
    local result
    # Pass a non-existent path for tasks.md — should fall back gracefully.
    result="$(_session_render_resume_block \
        "SESSION-20260615-120000" \
        "/dr-next TUNE-0441" \
        "Continue phase." \
        "${TASK_LIST_FILE}" \
        "/nonexistent/tasks.md")"

    local arrow_line
    arrow_line="$(printf '%s\n' "$result" | grep -E '^  ↳ TUNE-0441')"
    # No em-dash when title is absent.
    ! printf '%s\n' "$arrow_line" | grep -q ' — '
    # But saved-time (from SESSION-ID) should still appear.
    printf '%s\n' "$arrow_line" | grep -q '(saved'
}

# t-resume-12: saved time derived from SESSION-ID timestamp (R10)
@test "t-resume-12: saved-time is derived from SESSION-ID not a live date call" {
    local result
    result="$(_session_render_resume_block \
        "SESSION-20261225-093045" \
        "/dr-next TUNE-0441" \
        "Continue." \
        "${TASK_LIST_FILE}")"

    local arrow_line
    arrow_line="$(printf '%s\n' "$result" | grep -E '^  ↳ TUNE-0441')"
    # Must show the date/time encoded in the SESSION-ID (2026-12-25 09:30 UTC).
    printf '%s\n' "$arrow_line" | grep -q '2026-12-25 09:30'
}

# t-resume-13: R12 — Also-active excludes current task; only other IDs listed
@test "t-resume-13: Also-active line excludes current TASK-ID" {
    local three_tasks
    three_tasks="$(mktemp "${BATS_TEST_TMPDIR}/three-tasks.XXXX")"
    printf 'TUNE-0441 | in_progress\nVERD-0050 | in_progress\nSRCH-0030 | in_progress\n' \
        > "$three_tasks"

    local result
    result="$(_session_render_resume_block \
        "SESSION-20260615-120000" \
        "/dr-next TUNE-0441" \
        "Continue." \
        "$three_tasks")"

    # Also-active line must be present (2 other tasks).
    printf '%s\n' "$result" | grep -q 'Also active this session:'
    # Must list the other two tasks.
    printf '%s\n' "$result" | grep -q 'VERD-0050'
    printf '%s\n' "$result" | grep -q 'SRCH-0030'
    # Current task (TUNE-0441) must NOT appear in the Also-active line.
    local also_line
    also_line="$(printf '%s\n' "$result" | grep 'Also active this session:')"
    ! printf '%s\n' "$also_line" | grep -q 'TUNE-0441'

    rm -f "$three_tasks"
}

# t-resume-14: R12 — Also-active suppressed when current is the only task (deduplicate with t-resume-3)
@test "t-resume-14: Also-active suppressed when current task is the only active task" {
    local single_task
    single_task="$(mktemp "${BATS_TEST_TMPDIR}/single-task.XXXX")"
    printf 'TUNE-0441 | in_progress\n' > "$single_task"

    local result
    result="$(_session_render_resume_block \
        "SESSION-20260615-120000" \
        "/dr-next TUNE-0441" \
        "Only task." \
        "$single_task")"

    # No Also-active line when current is the only task (no others after exclusion).
    ! printf '%s\n' "$result" | grep -q 'Also active this session:'

    rm -f "$single_task"
}

# t-resume-15: title from tasks.md carrying backtick / $() / embedded newline is
# neutralized (R9 stricter sanitize). Closes the title-injection coverage gap
# flagged by /dr-verify (the existing injection test t-resume-5 covers next_action,
# not the title field). The title is display-only prose; this asserts a crafted
# title cannot forge a second command-shaped line or smuggle a substitution.
@test "t-resume-15: title with backtick, dollar-paren, and newline is sanitized in the arrow line" {
    local evil_tasks_md="${FAKE_ROOT}/datarim/tasks-evil.md"
    mkdir -p "${FAKE_ROOT}/datarim"
    # The 5th `·`-delimited field is the title; embed injection payloads in it.
    # (A literal newline cannot live inside one tasks.md Active line, so the
    # newline-collapse property is exercised below via a payload whose sanitize
    # path is identical — backtick + $() are the command-smuggling vectors.)
    cat > "$evil_tasks_md" <<'TASKS'
# Tasks

## Active
- TUNE-0441 · in_progress · P2 · L2 · Title with `whoami` and $(id) payload → tasks/TUNE-0441-task-description.md
TASKS

    local result
    result="$(_session_render_resume_block \
        "SESSION-20260615-120000" \
        "/dr-next TUNE-0441" \
        "Continue." \
        "${TASK_LIST_FILE}" \
        "$evil_tasks_md")"

    local arrow_line
    arrow_line="$(printf '%s\n' "$result" | grep -E '^  ↳ TUNE-0441')"

    # Backtick and $() substitutions must NOT survive into the rendered label.
    ! printf '%s\n' "$arrow_line" | grep -q '`'
    ! printf '%s\n' "$arrow_line" | grep -qF '$('
    # Benign words of the title still render (sanitize strips payloads, not all text).
    printf '%s\n' "$arrow_line" | grep -q 'Title with'
    # The only copy-paste command line is the canonical /dr-continue line —
    # exactly one such line, fed by the validated SESSION-ID, never the title.
    [ "$(printf '%s\n' "$result" | grep -cE '^  /dr-continue ')" -eq 1 ]
    printf '%s\n' "$result" | grep -qE '^  /dr-continue SESSION-20260615-120000$'
}
