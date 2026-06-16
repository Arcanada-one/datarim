#!/usr/bin/env bats
#
# Tests for dev-tools/check-session-handoff.sh
#
# Coverage:
#   - missing artefact → exit 1
#   - malformed frontmatter → exit 2
#   - symlink at artefact path → exit 2
#   - over-cap (>32768 bytes) → exit 2
#   - missing Layer-1 block → exit 2
#   - missing Layer-5 block → exit 2
#   - untagged claim-keyword in body → exit 2
#   - --self-test → exit 0

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
VALIDATOR="${REPO_ROOT}/dev-tools/check-session-handoff.sh"
SESSION_ID="SESSION-20260615-130000"

_session_path() {
    local root="$1"
    printf '%s/datarim/sessions/%s.session.md' "$root" "$SESSION_ID"
}

_valid_session_body() {
    cat <<'EOF'
## Layer 1 — Git State

repo: /Users/ug/code/myproject  HEAD: abc123  status: clean

## Layer 2 — Active Tasks

TUNE-0420 | in_progress

## Layer 3 — Related Files

- /Users/ug/arcanada/datarim/tasks/TUNE-0420-task-description.md

## Layer 4 — Open Questions

None.

## Layer 5 — Failed Approaches

Tried approach X, failed because Y.
EOF
}

_write_valid_session() {
    local root="$1"
    mkdir -p "${root}/datarim/sessions"
    local f
    f="$(_session_path "$root")"
    cat > "$f" <<EOF
---
artifact: session-handoff
schema_version: 1
session_id: ${SESSION_ID}
captured_at: 2026-06-15T13:00:00Z
captured_by: agent
recommended_next: /dr-next TUNE-0420
next_action: Continue Phase P2 implementation.
active_tasks:
  - TUNE-0420
---

$(_valid_session_body)
EOF
    chmod 600 "$f"
}

setup() {
    export FAKE_ROOT
    FAKE_ROOT="$(mktemp -d "${BATS_TEST_TMPDIR}/fake-repo.XXXX")"
}

# ---------------------------------------------------------------------------
# Missing artefact → exit 1
# ---------------------------------------------------------------------------

@test "missing artefact: exit 1" {
    run bash "${VALIDATOR}" --validate-frontmatter --session "${SESSION_ID}" --root "${FAKE_ROOT}"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Malformed frontmatter → exit 2
# ---------------------------------------------------------------------------

@test "malformed frontmatter: missing artifact field → exit 2" {
    mkdir -p "${FAKE_ROOT}/datarim/sessions"
    local f
    f="$(_session_path "${FAKE_ROOT}")"
    cat > "$f" <<EOF
---
schema_version: 1
session_id: ${SESSION_ID}
captured_at: 2026-06-15T13:00:00Z
captured_by: agent
recommended_next: /dr-next TUNE-0420
next_action: Continue.
active_tasks:
  - TUNE-0420
---

$(_valid_session_body)
EOF
    run bash "${VALIDATOR}" --validate-frontmatter --session "${SESSION_ID}" --root "${FAKE_ROOT}"
    [ "$status" -eq 2 ]
}

@test "malformed frontmatter: missing next_action field → exit 2" {
    mkdir -p "${FAKE_ROOT}/datarim/sessions"
    local f
    f="$(_session_path "${FAKE_ROOT}")"
    cat > "$f" <<EOF
---
artifact: session-handoff
schema_version: 1
session_id: ${SESSION_ID}
captured_at: 2026-06-15T13:00:00Z
captured_by: agent
recommended_next: /dr-next TUNE-0420
active_tasks:
  - TUNE-0420
---

$(_valid_session_body)
EOF
    run bash "${VALIDATOR}" --validate-frontmatter --session "${SESSION_ID}" --root "${FAKE_ROOT}"
    [ "$status" -eq 2 ]
}

@test "malformed frontmatter: missing recommended_next field → exit 2" {
    mkdir -p "${FAKE_ROOT}/datarim/sessions"
    local f
    f="$(_session_path "${FAKE_ROOT}")"
    cat > "$f" <<EOF
---
artifact: session-handoff
schema_version: 1
session_id: ${SESSION_ID}
captured_at: 2026-06-15T13:00:00Z
captured_by: agent
next_action: Continue.
active_tasks:
  - TUNE-0420
---

$(_valid_session_body)
EOF
    run bash "${VALIDATOR}" --validate-frontmatter --session "${SESSION_ID}" --root "${FAKE_ROOT}"
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Symlink at artefact path → exit 2 (T-7 consumer symmetry)
# ---------------------------------------------------------------------------

@test "symlink at artefact path: exit 2" {
    mkdir -p "${FAKE_ROOT}/datarim/sessions"
    local f
    f="$(_session_path "${FAKE_ROOT}")"
    local decoy
    decoy="$(mktemp "${BATS_TEST_TMPDIR}/decoy.XXXX")"
    printf 'decoy\n' > "$decoy"
    ln -sf "$decoy" "$f"
    run bash "${VALIDATOR}" --validate-frontmatter --session "${SESSION_ID}" --root "${FAKE_ROOT}"
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Over-cap → exit 2
# ---------------------------------------------------------------------------

@test "over-cap: file >32768 bytes → exit 2" {
    mkdir -p "${FAKE_ROOT}/datarim/sessions"
    local f
    f="$(_session_path "${FAKE_ROOT}")"
    # Write valid frontmatter then enormous body
    cat > "$f" <<'HDR'
---
artifact: session-handoff
schema_version: 1
session_id: SESSION-20260615-130000
captured_at: 2026-06-15T13:00:00Z
captured_by: agent
recommended_next: /dr-next TUNE-0420
next_action: Continue.
active_tasks:
  - TUNE-0420
---

## Layer 1 — Git State

HEAD: abc  status: clean

## Layer 5 — Failed Approaches

None.

HDR
    # Pad to well over 32768 bytes
    python3 -c "print('x' * 35000)" >> "$f"
    run bash "${VALIDATOR}" --validate-frontmatter --session "${SESSION_ID}" --root "${FAKE_ROOT}"
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Missing Layer-1 block → exit 2
# ---------------------------------------------------------------------------

@test "missing Layer-1 block: exit 2" {
    mkdir -p "${FAKE_ROOT}/datarim/sessions"
    local f
    f="$(_session_path "${FAKE_ROOT}")"
    cat > "$f" <<'EOF'
---
artifact: session-handoff
schema_version: 1
session_id: SESSION-20260615-130000
captured_at: 2026-06-15T13:00:00Z
captured_by: agent
recommended_next: /dr-next TUNE-0420
next_action: Continue.
active_tasks:
  - TUNE-0420
---

## Layer 5 — Failed Approaches

None.
EOF
    run bash "${VALIDATOR}" --validate-frontmatter --session "${SESSION_ID}" --root "${FAKE_ROOT}"
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Missing Layer-5 block → exit 2
# ---------------------------------------------------------------------------

@test "missing Layer-5 block: exit 2" {
    mkdir -p "${FAKE_ROOT}/datarim/sessions"
    local f
    f="$(_session_path "${FAKE_ROOT}")"
    cat > "$f" <<'EOF'
---
artifact: session-handoff
schema_version: 1
session_id: SESSION-20260615-130000
captured_at: 2026-06-15T13:00:00Z
captured_by: agent
recommended_next: /dr-next TUNE-0420
next_action: Continue.
active_tasks:
  - TUNE-0420
---

## Layer 1 — Git State

HEAD: abc  status: clean
EOF
    run bash "${VALIDATOR}" --validate-frontmatter --session "${SESSION_ID}" --root "${FAKE_ROOT}"
    [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Untagged claim-keyword → exit 2 (consumer-side mirror of writer reject)
# ---------------------------------------------------------------------------

@test "untagged claim: 'deployed' without tag → exit 2" {
    mkdir -p "${FAKE_ROOT}/datarim/sessions"
    local f
    f="$(_session_path "${FAKE_ROOT}")"
    cat > "$f" <<'EOF'
---
artifact: session-handoff
schema_version: 1
session_id: SESSION-20260615-130000
captured_at: 2026-06-15T13:00:00Z
captured_by: agent
recommended_next: /dr-next TUNE-0420
next_action: Continue.
active_tasks:
  - TUNE-0420
---

## Layer 1 — Git State

HEAD: abc  status: clean

## Layer 5 — Failed Approaches

None.

The service was deployed to production.
EOF
    run bash "${VALIDATOR}" --validate-frontmatter --session "${SESSION_ID}" --root "${FAKE_ROOT}"
    [ "$status" -eq 2 ]
}

@test "tagged claim: 'deployed verified: confirmed by health check' → exit 0" {
    _write_valid_session "${FAKE_ROOT}"
    # Append a tagged claim to the body
    local f
    f="$(_session_path "${FAKE_ROOT}")"
    printf '\nThe service was deployed to production. verified: health check passed at 14:00\n' >> "$f"
    run bash "${VALIDATOR}" --validate-frontmatter --session "${SESSION_ID}" --root "${FAKE_ROOT}"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Happy path: valid file → exit 0
# ---------------------------------------------------------------------------

@test "valid session file: exit 0" {
    _write_valid_session "${FAKE_ROOT}"
    run bash "${VALIDATOR}" --validate-frontmatter --session "${SESSION_ID}" --root "${FAKE_ROOT}"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# --self-test → exit 0
# ---------------------------------------------------------------------------

@test "--self-test: exit 0" {
    run bash "${VALIDATOR}" --self-test
    [ "$status" -eq 0 ]
}
