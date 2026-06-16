#!/usr/bin/env bash
# Datarim session-handoff artefact validator.
#
# Modes:
#   --session <SESSION-ID> [--root <repo>]              presence + light schema
#   --validate-frontmatter --session <ID> [--root <r>]  strict schema check
#   --self-test                                         synthetic smoke
#
# Exit codes:
#   0  ok
#   1  artefact missing
#   2  malformed (missing field / symlink / over-cap / claim-keyword / missing layer block)
#   3  usage error
#
# Security:
#   F9 (symlink rejection) — mirrors check-stage-snapshot-on-exit.sh pattern.
#   Claim-provenance check (consumer side of writer's wish-5 enforcement).

set -euo pipefail

# Mandatory frontmatter scalar fields.
readonly SESSION_REQUIRED_SCALAR_FIELDS=(
    artifact
    schema_version
    session_id
    captured_at
    captured_by
    recommended_next
    next_action
)

readonly SESSION_MAX_BYTES=32768

# Claim keywords (POSIX ERE, grep -E — grep -P unavailable on BSD/macOS).
readonly SESSION_CLAIM_PATTERN='(pushed|merged|deployed|green|passing)'

usage() {
    cat >&2 <<'USAGE'
Usage:
  check-session-handoff.sh --session <SESSION-ID> [--root <repo>]
  check-session-handoff.sh --validate-frontmatter --session <ID> [--root <r>]
  check-session-handoff.sh --self-test

Exit codes: 0 ok | 1 missing | 2 malformed | 3 usage.
USAGE
}

session_path() {
    local root="$1" session_id="$2"
    printf '%s/datarim/sessions/%s.session.md' "$root" "$session_id"
}

extract_frontmatter() {
    local file="$1"
    awk '
        BEGIN { in_fm = 0 }
        /^---[[:space:]]*$/ {
            if (in_fm == 0) { in_fm = 1; next }
            if (in_fm == 1) { exit }
        }
        in_fm == 1 { print }
    ' "$file"
}

frontmatter_has_field() {
    local fm="$1" field="$2"
    printf '%s\n' "$fm" | grep -Eq "^${field}:[[:space:]]"
}

validate_frontmatter() {
    local file="$1"
    [ -r "$file" ] || return 1

    # F9: reject symlinks (T-7 consumer symmetry).
    if [ -L "$file" ]; then
        printf 'check-session-handoff: artefact path is a symlink (rejected)\n' >&2
        return 2
    fi

    # Cap check: file must not exceed 32768 bytes.
    local fsize
    fsize="$(wc -c < "$file" | tr -d ' ')"
    if [ "$fsize" -gt "$SESSION_MAX_BYTES" ]; then
        printf 'check-session-handoff: artefact exceeds 32768 byte cap (%s bytes)\n' "$fsize" >&2
        return 2
    fi

    local fm
    fm="$(extract_frontmatter "$file")"
    [ -n "$fm" ] || return 2

    # Check required scalar fields.
    for field in "${SESSION_REQUIRED_SCALAR_FIELDS[@]}"; do
        if ! frontmatter_has_field "$fm" "$field"; then
            printf 'check-session-handoff: missing mandatory field %q\n' "$field" >&2
            return 2
        fi
    done

    # Check active_tasks list header.
    if ! printf '%s\n' "$fm" | grep -Eq '^active_tasks:[[:space:]]*$'; then
        printf 'check-session-handoff: missing active_tasks list\n' >&2
        return 2
    fi

    # Layer-1 block check: body must contain ## Layer 1.
    if ! grep -qF '## Layer 1' "$file"; then
        printf 'check-session-handoff: missing Layer-1 block (## Layer 1)\n' >&2
        return 2
    fi

    # Layer-5 block check: body must contain ## Layer 5.
    if ! grep -qF '## Layer 5' "$file"; then
        printf 'check-session-handoff: missing Layer-5 block (## Layer 5)\n' >&2
        return 2
    fi

    # Claim-provenance check (consumer side of writer's wish-5 enforcement).
    # Any body line with a claim keyword MUST carry verified: or assumed:.
    # grep -E is POSIX-portable (no -P on macOS/BSD).
    if grep -E -i "${SESSION_CLAIM_PATTERN}" "$file" 2>/dev/null \
        | grep -v -E '(verified:|assumed:|^---$|^artifact:|^schema_version:|^session_id:|^captured_at:|^captured_by:|^recommended_next:|^next_action:|^active_tasks:|^  - )' \
        | grep -q '.'; then
        printf 'check-session-handoff: untagged claim-keyword found in artefact body.\n' >&2
        printf 'check-session-handoff: every claim line must carry verified: or assumed: tag.\n' >&2
        return 2
    fi

    return 0
}

self_test() {
    local tmp rc
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/datarim/sessions"
    cat > "$tmp/datarim/sessions/SESSION-20260615-000000.session.md" <<'SESS'
---
artifact: session-handoff
schema_version: 1
session_id: SESSION-20260615-000000
captured_at: 2026-06-15T00:00:00Z
captured_by: agent
recommended_next: /dr-next TUNE-0001
next_action: Continue Phase P2 implementation.
active_tasks:
  - TUNE-0001
---

## Layer 1 — Git State

repo: /test  HEAD: abc123  status: clean

## Layer 2 — Active Tasks

TUNE-0001 | in_progress

## Layer 3 — Related Files

None.

## Layer 4 — Open Questions

None.

## Layer 5 — Failed Approaches

None attempted yet.
SESS
    if validate_frontmatter "$tmp/datarim/sessions/SESSION-20260615-000000.session.md"; then
        rc=0
    else
        rc=$?
    fi
    rm -rf "$tmp"
    return "$rc"
}

main() {
    local mode=""
    local session_id=""
    local root=""

    if [ $# -eq 0 ]; then
        usage
        return 3
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            --session)            session_id="$2"; shift 2 ;;
            --root)               root="$2"; shift 2 ;;
            --validate-frontmatter) mode="validate"; shift ;;
            --self-test)          mode="selftest"; shift ;;
            -h|--help) usage; return 0 ;;
            *) usage; return 3 ;;
        esac
    done

    # Default --root via the canonical resolver.
    if [ -z "$root" ]; then
        local _lib
        _lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib" 2>/dev/null && pwd)"
        if [ -n "$_lib" ] && [ -f "$_lib/resolve-datarim-root.sh" ]; then
            # shellcheck source=/dev/null
            . "$_lib/resolve-datarim-root.sh"
            root="$(resolve_datarim_root 2>/dev/null || true)"
        fi
        [ -z "$root" ] && root="$PWD"
    fi

    if [ "$mode" = "selftest" ]; then
        if self_test; then
            printf 'check-session-handoff: self-test OK\n'
            return 0
        else
            return 2
        fi
    fi

    if [ -z "$session_id" ]; then
        usage
        return 3
    fi

    local file
    file="$(session_path "$root" "$session_id")"

    if [ ! -e "$file" ] && [ ! -L "$file" ]; then
        return 1
    fi

    if [ "$mode" = "validate" ]; then
        validate_frontmatter "$file"
        return $?
    fi

    # Default (presence) mode — still does full schema check.
    validate_frontmatter "$file"
    return $?
}

main "$@"
