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
