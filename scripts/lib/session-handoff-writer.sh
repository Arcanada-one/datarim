#!/usr/bin/env bash
# Datarim cross-runtime session-handoff writer.
#
# Writes (or appends to) datarim/sessions/{SESSION-ID}.session.md with
# append-only semantics — a second /dr-save in the same session appends a
# new dated block, never truncates prior blocks.
#
# Sibling of snapshot-writer.sh; reuses acquire_plugin_lock /
# release_plugin_lock, assert_not_nested_datarim, and the atomic
# write-temp-rename / chmod 600 pattern.
#
# New vs snapshot writer:
#   (a) 32768-byte cap with per-layer sub-budgets (L1 + L5 protected).
#   (b) Append-only decision-log semantics — a second call appends.
#   (c) Session-id (timestamp) cardinality instead of TASK-ID.
#   (d) Claim-provenance enforcement: any body line matching the
#       claim-keyword set (pushed|merged|deployed|green|passing) MUST
#       carry a verified: or assumed: tag — the writer rejects (exit 1)
#       an untagged claim before write.
#   (e) Secret scan-and-redact pass over the body before write (T-8).
#
# Contract: see skills/session-handoff-writer/SKILL.md.
#
# Exit codes: 0 ok | 1 IO/validation | 2 usage | 3 lock-timeout

set -euo pipefail

_SESSION_WRITER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=plugin-system.sh
. "${_SESSION_WRITER_LIB_DIR}/plugin-system.sh"
# shellcheck source=resolve-datarim-root.sh
. "${_SESSION_WRITER_LIB_DIR}/resolve-datarim-root.sh"

# --- Constants ---------------------------------------------------------------

readonly SESSION_ID_RE='^SESSION-[0-9]{8}-[0-9]{6}$'
readonly SESSION_MAX_BYTES=32768
readonly SESSION_TRUNCATION_MARKER='<!-- session-truncated: Layer-3/4 content dropped to honour 32 KB cap -->'

# Claim keywords that require a provenance tag (verified: or assumed:).
# Uses POSIX ERE via grep -E — portable on macOS/BSD and Linux.
readonly CLAIM_KEYWORD_PATTERN='(pushed|merged|deployed|green|passing)'

# Secret-scan patterns (POSIX ERE, portable grep -E).
# Matches common API key / credential shapes for redaction (T-8).
# Pattern list is intentionally conservative — false-negatives are
# acceptable; false-positives on normal prose must be minimised.
readonly SECRET_PATTERNS='(AKIA[0-9A-Z]{16}|-----BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY-----|client_secret_[0-9a-zA-Z_-]{8,}|ghp_[0-9a-zA-Z]{36}|ghs_[0-9a-zA-Z]{36}|sk-[0-9a-zA-Z]{48})'

# ---------------------------------------------------------------------------
# Usage / validation helpers
# ---------------------------------------------------------------------------

_session_writer_usage() {
    cat >&2 <<'USAGE'
Usage: write_session_handoff \
    --root <DATARIM_ROOT> \
    --session <SESSION-YYYYMMDD-HHMMSS> \
    --captured-by <agent|operator> \
    --recommended-next <command> \
    --next-action <single-line description> \
    --active-tasks-file <path>  \
    --body-file <path> \
    [--captured-at <ISO-8601 UTC>]

Exit codes: 0 ok | 1 IO/validation | 2 usage | 3 lock-timeout
USAGE
}

_validate_session_id() {
    local id="$1"
    [[ "$id" =~ $SESSION_ID_RE ]]
}

# ---------------------------------------------------------------------------
# Claim-provenance check (T-2 correctness + security adjacency)
#
# Scans body for lines containing a claim keyword not followed (on the same
# line) by verified: or assumed:.  Returns 1 if any untagged claim found.
# Uses grep -E (POSIX ERE) — grep -P unavailable on BSD/macOS.
# ---------------------------------------------------------------------------

_check_claim_provenance() {
    local body_file="$1"

    # Line contains a claim keyword AND does NOT contain verified: or assumed:
    if grep -E -i "${CLAIM_KEYWORD_PATTERN}" "$body_file" 2>/dev/null \
        | grep -v -E '(verified:|assumed:)' \
        | grep -q '.'; then
        printf 'write_session_handoff: untagged claim-keyword found in body.\n' >&2
        printf 'write_session_handoff: every line containing pushed|merged|deployed|green|passing\n' >&2
        printf 'write_session_handoff: MUST carry a verified: or assumed: tag on the same line.\n' >&2
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Secret scan-and-redact (T-8)
#
# Reads body_file, replaces matching secret patterns with [REDACTED],
# writes to out_file. Reports count to stderr. Uses sed with POSIX ERE.
# ---------------------------------------------------------------------------

_secret_redact() {
    local body_file="$1"
    local out_file="$2"

    # Count matches for the stderr report.
    local count
    count="$(grep -E -o "${SECRET_PATTERNS}" "$body_file" 2>/dev/null | wc -l | tr -d ' ')" || count=0

    if [ "$count" -gt 0 ]; then
        printf 'write_session_handoff: T-8 redacted %s secret pattern(s) in body.\n' "$count" >&2
    fi

    # sed -E is POSIX-standard on both macOS and Linux. Use a temp file to
    # avoid in-place portability issues.
    sed -E "s/${SECRET_PATTERNS}/[REDACTED]/g" "$body_file" > "$out_file"
}

# ---------------------------------------------------------------------------
# Render YAML frontmatter block (Security Mandate S1 — quoted heredoc,
# printf -- per field, no shell expansion).
# ---------------------------------------------------------------------------

_session_render_frontmatter() {
    local session_id="$1"
    local captured_at="$2"
    local captured_by="$3"
    local recommended_next="$4"
    local next_action="$5"
    local tasks_file="$6"

    printf -- '---\n'
    printf -- 'artifact: session-handoff\n'
    printf -- 'schema_version: 1\n'
    printf -- 'session_id: %s\n' "$session_id"
    printf -- 'captured_at: %s\n' "$captured_at"
    printf -- 'captured_by: %s\n' "$captured_by"
    printf -- 'recommended_next: %s\n' "$recommended_next"
    printf -- 'next_action: %s\n' "$next_action"
    printf -- 'active_tasks:\n'
    if [ -n "$tasks_file" ] && [ -f "$tasks_file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            [ -z "$line" ] && continue
            # Extract task-id prefix (before | or space) for the list.
            local task_id
            task_id="$(printf '%s' "$line" | awk -F'[| ]' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$1); print $1}')"
            [ -n "$task_id" ] && printf -- '  - %s\n' "$task_id"
        done < "$tasks_file"
    fi
    printf -- '---\n\n'
}

# ---------------------------------------------------------------------------
# Per-layer cap enforcement
#
# Protects Layer-1 and Layer-5 blocks from truncation.
# Truncates Layer-3 and Layer-4 content first when the body exceeds the
# available budget. Returns a (possibly truncated) body in out_file.
# ---------------------------------------------------------------------------

_enforce_layer_cap() {
    local body_file="$1"    # input (already redacted)
    local out_file="$2"     # output (capped body)
    local max_body="$3"     # bytes available for the body

    local body_bytes
    body_bytes="$(wc -c < "$body_file" | tr -d ' ')"

    if [ "$body_bytes" -le "$max_body" ]; then
        cp "$body_file" "$out_file"
        return 0
    fi

    # Need to truncate. Strategy:
    # 1. Extract Layer-1 block (everything between ## Layer 1 and the next ## Layer)
    # 2. Extract Layer-5 block (everything after ## Layer 5)
    # 3. Fill remaining budget with layers 2-4 (truncated if needed)
    # 4. Reassemble: protected-L1 + (truncated L2-4) + protected-L5 + marker

    local l1_file l5_file middle_file
    l1_file="$(mktemp "${TMPDIR:-/tmp}/session-l1.XXXXXX")"
    l5_file="$(mktemp "${TMPDIR:-/tmp}/session-l5.XXXXXX")"
    middle_file="$(mktemp "${TMPDIR:-/tmp}/session-mid.XXXXXX")"

    # Extract Layer-1 block (from ## Layer 1 heading up to the next ## Layer heading)
    awk 'BEGIN{in_l1=0}
         /^## Layer 1/{in_l1=1; print; next}
         in_l1 && /^## Layer [2-9]/{in_l1=0; next}
         in_l1{print}' "$body_file" > "$l1_file" || true

    # Extract Layer-5 block (from ## Layer 5 to end)
    awk '/^## Layer 5/{found=1} found{print}' "$body_file" > "$l5_file" || true

    # Extract middle (## Layer 2 through end of ## Layer 4)
    awk 'BEGIN{in_mid=0}
         /^## Layer [234]/{in_mid=1}
         in_mid && /^## Layer 5/{in_mid=0; next}
         in_mid{print}' "$body_file" > "$middle_file" || true

    local l1_bytes l5_bytes marker_bytes
    l1_bytes="$(wc -c < "$l1_file" | tr -d ' ')"
    l5_bytes="$(wc -c < "$l5_file" | tr -d ' ')"
    marker_bytes="$(printf '%s\n' "$SESSION_TRUNCATION_MARKER" | wc -c | tr -d ' ')"

    local middle_budget
    middle_budget=$(( max_body - l1_bytes - l5_bytes - marker_bytes - 4 ))
    if [ "$middle_budget" -lt 0 ]; then
        middle_budget=0
    fi

    local middle_chunk
    middle_chunk="$(mktemp "${TMPDIR:-/tmp}/session-mid-chunk.XXXXXX")"
    if [ -s "$middle_file" ]; then
        head -c "$middle_budget" "$middle_file" | \
            iconv -c -f UTF-8 -t UTF-8 2>/dev/null > "$middle_chunk" || \
            head -c "$middle_budget" "$middle_file" > "$middle_chunk" || true
    else
        printf '' > "$middle_chunk"
    fi

    {
        cat "$l1_file"
        printf '\n'
        cat "$middle_chunk"
        printf '\n%s\n' "$SESSION_TRUNCATION_MARKER"
        cat "$l5_file"
    } > "$out_file"

    rm -f "$l1_file" "$l5_file" "$middle_file" "$middle_chunk"
    return 0
}

# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

write_session_handoff() {
    if [ "${DATARIM_DISABLE_SESSION_HANDOFF:-0}" = "1" ]; then
        return 0
    fi

    local root="" session_id="" captured_by=""
    local recommended_next="" next_action=""
    local active_tasks_file="" body_file=""
    local captured_at=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --root)               root="$2";               shift 2 ;;
            --session)            session_id="$2";          shift 2 ;;
            --captured-by)        captured_by="$2";         shift 2 ;;
            --recommended-next)   recommended_next="$2";    shift 2 ;;
            --next-action)        next_action="$2";         shift 2 ;;
            --active-tasks-file)  active_tasks_file="$2";   shift 2 ;;
            --body-file)          body_file="$2";           shift 2 ;;
            --captured-at)        captured_at="$2";         shift 2 ;;
            -h|--help) _session_writer_usage; return 2 ;;
            *) printf 'write_session_handoff: unknown arg %q\n' "$1" >&2
               _session_writer_usage; return 2 ;;
        esac
    done

    # Argument validation.
    if [ -z "$root" ] || [ -z "$session_id" ] || [ -z "$captured_by" ] \
       || [ -z "$recommended_next" ] || [ -z "$next_action" ] \
       || [ -z "$body_file" ]; then
        _session_writer_usage
        return 2
    fi

    # T-1: validate session-id against the canonical regex.
    if ! _validate_session_id "$session_id"; then
        printf 'write_session_handoff: invalid session-id %q (regex %s)\n' \
            "$session_id" "$SESSION_ID_RE" >&2
        return 1
    fi

    if [ ! -f "$body_file" ]; then
        printf 'write_session_handoff: body file missing: %s\n' "$body_file" >&2
        return 1
    fi

    if [ ! -d "$root" ]; then
        printf 'write_session_handoff: root not a directory: %s\n' "$root" >&2
        return 1
    fi

    # T-4: refuse a root inside a datarim/ (nesting vector).
    if ! assert_not_nested_datarim "$root"; then
        return 1
    fi

    if [ -z "$captured_at" ]; then
        captured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fi

    # Claim-provenance check (wish-5, writer side): exit 1 on untagged claim.
    if ! _check_claim_provenance "$body_file"; then
        return 1
    fi

    local sessions_dir="${root}/datarim/sessions"
    local lock_dir="${sessions_dir}/.lock.${session_id}"
    local final_path="${sessions_dir}/${session_id}.session.md"
    local tmp_path="${final_path}.tmp.$$"

    mkdir -p "$sessions_dir"
    chmod 700 "$sessions_dir" 2>/dev/null || true

    local timeout="${DR_SESSION_LOCK_TIMEOUT:-60}"
    if ! acquire_plugin_lock "$lock_dir" "$timeout"; then
        printf 'write_session_handoff: lock timeout (%ss) on %s\n' \
            "$timeout" "$lock_dir" >&2
        return 3
    fi
    # shellcheck disable=SC2064  # expand session_id NOW for the trap
    trap "release_plugin_lock \"$lock_dir\"; rm -f \"$tmp_path\"" EXIT INT TERM

    # T-7: pre-unlink symlink at target path.
    if [ -L "$final_path" ]; then
        rm -f "$final_path"
    fi

    # T-8: secret scan-and-redact — write redacted body to temp file.
    local redacted_body
    redacted_body="$(mktemp "${TMPDIR:-/tmp}/session-redacted.XXXXXX")"
    _secret_redact "$body_file" "$redacted_body"

    # Per-layer cap enforcement: compute how much body budget is available.
    # Render a probe frontmatter (size_bytes unknown, use 0) to measure fm size.
    local fm_probe fm_bytes
    fm_probe="$(_session_render_frontmatter \
        "$session_id" "$captured_at" "$captured_by" \
        "$recommended_next" "$next_action" "$active_tasks_file")"
    fm_bytes="$(printf '%s' "$fm_probe" | wc -c | tr -d ' ')"

    local marker_bytes
    marker_bytes="$(printf '%s\n' "$SESSION_TRUNCATION_MARKER" | wc -c | tr -d ' ')"

    # Append-only: if the file already exists, we will append a new dated
    # block. The cap applies to the new block only; the existing file content
    # is preserved in its entirety (append-only decision-log semantics).
    local existing_bytes=0
    local separator_bytes=0
    if [ -f "$final_path" ] && [ ! -L "$final_path" ]; then
        existing_bytes="$(wc -c < "$final_path" | tr -d ' ')"
        # 2-newline separator between blocks.
        separator_bytes=2
    fi

    # Maximum bytes for the new block (frontmatter + body).
    local max_new_block
    max_new_block=$(( SESSION_MAX_BYTES - existing_bytes - separator_bytes ))
    if [ "$max_new_block" -lt 64 ]; then
        # File already at cap — warn and skip (fail-closed warn-and-skip).
        printf 'write_session_handoff: session file at capacity, new block not written.\n' >&2
        rm -f "$redacted_body"
        release_plugin_lock "$lock_dir"
        trap - EXIT INT TERM
        return 0
    fi

    local max_body
    max_body=$(( max_new_block - fm_bytes - marker_bytes - 4 ))
    if [ "$max_body" -lt 0 ]; then
        max_body=0
    fi

    # Apply per-layer cap.
    local capped_body
    capped_body="$(mktemp "${TMPDIR:-/tmp}/session-capped.XXXXXX")"
    _enforce_layer_cap "$redacted_body" "$capped_body" "$max_body"
    rm -f "$redacted_body"

    # Build the new block: frontmatter + capped body.
    # NOTE: $fm_probe is captured via $(...) which strips the renderer's
    # trailing "---\n\n", so the printf MUST re-emit a newline separator —
    # otherwise the body's first line glues onto the closing "---" as
    # "---## Layer 1", breaking strict YAML-frontmatter parsers.
    {
        printf '%s\n\n' "$fm_probe"
        cat "$capped_body"
    } > "$tmp_path"
    rm -f "$capped_body"

    chmod 600 "$tmp_path" 2>/dev/null || true

    # fsync (best-effort, same pattern as snapshot-writer).
    dd if="$tmp_path" of="$tmp_path" conv=notrunc,fsync count=0 2>/dev/null || true

    # Atomic append or rename.
    if [ -f "$final_path" ] && [ ! -L "$final_path" ] && [ "$existing_bytes" -gt 0 ]; then
        # Append-only: copy existing content + separator + new block to tmp,
        # then atomic rename (preserves permissions).
        local merge_tmp
        merge_tmp="${final_path}.merge.$$"
        {
            cat "$final_path"
            printf '\n\n'
            cat "$tmp_path"
        } > "$merge_tmp"
        chmod 600 "$merge_tmp" 2>/dev/null || true
        mv -f "$merge_tmp" "$final_path"
        rm -f "$tmp_path"
    else
        mv -f "$tmp_path" "$final_path"
    fi

    release_plugin_lock "$lock_dir"
    trap - EXIT INT TERM
    return 0
}

# If sourced, expose write_session_handoff. If invoked directly, dispatch.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    write_session_handoff "$@"
fi
