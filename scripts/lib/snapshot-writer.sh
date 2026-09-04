#!/usr/bin/env bash
# Datarim per-task stage-snapshot writer (TUNE-0254).
#
# Writes datarim/snapshots/{TASK-ID}.snapshot.md with overwrite semantics.
# Concurrent-safe via mkdir-based atomic lock (acquire_plugin_lock pattern).
# File hard-capped at 8192 bytes; oversize bodies receive a truncation marker.
#
# Contract: see skills/stage-snapshot-writer/SKILL.md.

set -euo pipefail

SNAPSHOT_WRITER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=plugin-system.sh
. "${SNAPSHOT_WRITER_LIB_DIR}/plugin-system.sh"
# shellcheck source=resolve-datarim-root.sh
. "${SNAPSHOT_WRITER_LIB_DIR}/resolve-datarim-root.sh"

readonly SNAPSHOT_TASK_ID_RE='^[A-Z][A-Z0-9]{1,9}-[0-9]{4}(-[A-Za-z0-9]+)*$'
readonly SNAPSHOT_STAGE_RE='^(init|prd|plan|design|do|qa|verify|compliance|archive|edit|publish|write|dream|doctor|optimize|auto)$'
readonly SNAPSHOT_MAX_BYTES=8192
readonly SNAPSHOT_TRUNCATION_MARKER='<!-- snapshot-truncated, full ответ см. session jsonl -->'

snapshot_writer_usage() {
    cat >&2 <<'USAGE'
Usage: write_stage_snapshot \
    --root <DATARIM_ROOT> \
    --task <TASK-ID> \
    --stage <plan|prd|do|...> \
    --command </dr-name> \
    --captured-by <agent|operator> \
    --recommended-next </dr-name> \
    --options-file <path> \
    --body-file <path> \
    [--captured-at <ISO-8601 UTC>]

Exit codes: 0 ok | 1 IO/validation | 2 usage | 3 lock-timeout
USAGE
}

# Validate a TASK-ID against the canonical regex. Echoes nothing.
_snapshot_validate_task_id() {
    local id="$1"
    [[ "$id" =~ $SNAPSHOT_TASK_ID_RE ]]
}

# Validate stage enum.
_snapshot_validate_stage() {
    local stage="$1"
    [[ "$stage" =~ $SNAPSHOT_STAGE_RE ]]
}

# Build YAML frontmatter from collected args. Stdout = frontmatter bytes.
# Uses quoted heredoc — no shell expansion inside (Security Mandate S1).
_snapshot_render_frontmatter() {
    local task_id="$1" stage="$2" command="$3" captured_at="$4" captured_by="$5"
    local recommended_next="$6" options_file="$7" size_bytes="$8" truncated="$9"

    printf -- '---\n'
    printf -- 'task_id: %s\n' "$task_id"
    printf -- 'artifact: stage-snapshot\n'
    printf -- 'schema_version: 1\n'
    printf -- 'stage: %s\n' "$stage"
    printf -- 'command: %s\n' "$command"
    printf -- 'captured_at: %s\n' "$captured_at"
    printf -- 'captured_by: %s\n' "$captured_by"
    printf -- 'recommended_next: %s\n' "$recommended_next"
    printf -- 'options:\n'
    if [ -n "$options_file" ] && [ -f "$options_file" ]; then
        while IFS= read -r opt || [ -n "$opt" ]; do
            [ -z "$opt" ] && continue
            printf -- '  - %s\n' "$opt"
        done < "$options_file"
    fi
    printf -- 'size_bytes: %s\n' "$size_bytes"
    printf -- 'truncated: %s\n' "$truncated"
    printf -- '---\n\n'
}

# Guarantee the emitted frontmatter footer is always followed by a blank body separator
# line, even if the transport path strips trailing newlines in the future.
_snapshot_render_frontmatter_terminal() {
    local path="$1"
    local tail2_hex

    # shellcheck disable=SC2016
    # We compare trailing bytes (hex), because command substitution drops trailing
    # newlines. A single quoted '---\n\n' can still look wrong after substitution.
    while :; do
        tail2_hex="$(tail -c 2 "$path" 2>/dev/null \
            | od -An -t x1 \
            | tr -d ' \n' || true)"
        if [ "$tail2_hex" = "0a0a" ]; then
            return 0
        fi
        printf '\n' >> "$path"
    done
}

# Render frontmatter until its declared size is the exact fixed point of:
#
#   frontmatter bytes (including decimal size width) + final body bytes
#
# The decimal field is self-referential: changing 9999 to 10000 makes the
# frontmatter one byte longer. A single recomputation is therefore not enough
# at a decimal-width boundary. The function writes to a file so trailing
# newlines stay byte-exact, prints the converged size, and fails closed if the
# bounded monotone iteration does not converge.
_snapshot_render_exact_frontmatter() {
    local task_id="$1" stage="$2" command="$3" captured_at="$4" captured_by="$5"
    local recommended_next="$6" options_file="$7" body_bytes="$8"
    local size_bytes="$9" truncated="${10}" output_file="${11}"
    local iteration fm_bytes actual_size

    for iteration in 1 2 3 4 5 6 7 8; do
        _snapshot_render_frontmatter \
            "$task_id" "$stage" "$command" "$captured_at" "$captured_by" \
            "$recommended_next" "$options_file" "$size_bytes" "$truncated" \
            > "$output_file"
        _snapshot_render_frontmatter_terminal "$output_file"
        fm_bytes="$(wc -c < "$output_file" | tr -d ' ')"
        actual_size=$(( fm_bytes + body_bytes ))
        if [ "$actual_size" -eq "$size_bytes" ]; then
            printf '%s\n' "$actual_size"
            return 0
        fi
        size_bytes="$actual_size"
    done

    printf 'write_stage_snapshot: exact size did not converge after %s iterations\n' \
        "$iteration" >&2
    return 1
}

# Trap state is stored as data, never interpolated into trap source. A root
# path may legally contain shell metacharacters; reparsing such a path in an
# EXIT trap would turn it into executable code and could also address the
# wrong lock directory.
_snapshot_writer_cleanup_lock_dir=""
_snapshot_writer_cleanup_tmp_path=""
_snapshot_writer_cleanup_body_tmp=""
_snapshot_writer_cleanup_raw_chunk=""
_snapshot_writer_cleanup_fm_probe=""
_snapshot_writer_cleanup_fm_final=""

_snapshot_writer_cleanup() {
    local status="${1:-0}"

    trap - EXIT INT TERM
    if [ -n "$_snapshot_writer_cleanup_lock_dir" ]; then
        release_plugin_lock "$_snapshot_writer_cleanup_lock_dir"
    fi
    rm -f -- \
        "$_snapshot_writer_cleanup_tmp_path" \
        "$_snapshot_writer_cleanup_body_tmp" \
        "$_snapshot_writer_cleanup_raw_chunk" \
        "$_snapshot_writer_cleanup_fm_probe" \
        "$_snapshot_writer_cleanup_fm_final"

    _snapshot_writer_cleanup_lock_dir=""
    _snapshot_writer_cleanup_tmp_path=""
    _snapshot_writer_cleanup_body_tmp=""
    _snapshot_writer_cleanup_raw_chunk=""
    _snapshot_writer_cleanup_fm_probe=""
    _snapshot_writer_cleanup_fm_final=""
    return "$status"
}

# Public entry point.
write_stage_snapshot() {
    if [ "${DATARIM_DISABLE_SNAPSHOT:-0}" = "1" ]; then
        return 0
    fi

    local root="" task_id="" stage="" command="" captured_by=""
    local recommended_next="" options_file="" body_file=""
    local captured_at=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --root) root="$2"; shift 2 ;;
            --task) task_id="$2"; shift 2 ;;
            --stage) stage="$2"; shift 2 ;;
            --command) command="$2"; shift 2 ;;
            --captured-by) captured_by="$2"; shift 2 ;;
            --recommended-next) recommended_next="$2"; shift 2 ;;
            --options-file) options_file="$2"; shift 2 ;;
            --body-file) body_file="$2"; shift 2 ;;
            --captured-at) captured_at="$2"; shift 2 ;;
            -h|--help) snapshot_writer_usage; return 2 ;;
            *) printf 'write_stage_snapshot: unknown arg %q\n' "$1" >&2
               snapshot_writer_usage; return 2 ;;
        esac
    done

    # Argument validation. Name the specific missing flag(s) before the usage
    # block so callers do not have to re-read the whole usage to find the gap.
    # --options-file is intentionally NOT required (defaults to an empty options
    # list); only these seven flags are mandatory.
    local missing=""
    [ -z "$root" ]             && missing="$missing --root"
    [ -z "$task_id" ]          && missing="$missing --task"
    [ -z "$stage" ]            && missing="$missing --stage"
    [ -z "$command" ]          && missing="$missing --command"
    [ -z "$captured_by" ]      && missing="$missing --captured-by"
    [ -z "$recommended_next" ] && missing="$missing --recommended-next"
    [ -z "$body_file" ]        && missing="$missing --body-file"
    if [ -n "$missing" ]; then
        printf 'write_stage_snapshot: missing required flag(s):%s\n' "$missing" >&2
        snapshot_writer_usage
        return 2
    fi

    if ! _snapshot_validate_task_id "$task_id"; then
        printf 'write_stage_snapshot: invalid TASK-ID %q (regex %s)\n' \
            "$task_id" "$SNAPSHOT_TASK_ID_RE" >&2
        return 1
    fi

    if ! _snapshot_validate_stage "$stage"; then
        printf 'write_stage_snapshot: invalid stage %q\n' "$stage" >&2
        return 1
    fi

    if [ ! -f "$body_file" ]; then
        printf 'write_stage_snapshot: body file missing: %s\n' "$body_file" >&2
        return 1
    fi

    if [ ! -d "$root" ]; then
        printf 'write_stage_snapshot: root not a directory: %s\n' "$root" >&2
        return 1
    fi

    # --root is repo-root by canon (resolve-datarim-root.sh). Refuse a root that
    # is itself inside a datarim/ — building "$root/datarim/snapshots" from such
    # a root is the datarim/datarim/ nesting vector (PRD V-AC-5). Reject loudly
    # rather than silently writing a misplaced KB.
    if ! assert_not_nested_datarim "$root"; then
        return 1
    fi

    if [ -z "$captured_at" ]; then
        captured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fi

    local snapshots_dir="$root/datarim/snapshots"
    local lock_dir="$snapshots_dir/.lock.${task_id}"
    local final_path="$snapshots_dir/${task_id}.snapshot.md"
    local tmp_path="${final_path}.tmp.$$"
    local body_tmp="${tmp_path}.body"
    local raw_chunk="${body_tmp}.raw"
    local fm_probe_path="${tmp_path}.frontmatter.probe"
    local fm_final_path="${tmp_path}.frontmatter"

    mkdir -p "$snapshots_dir"
    chmod 700 "$snapshots_dir" 2>/dev/null || true

    local timeout="${DR_SNAPSHOT_LOCK_TIMEOUT:-60}"
    if ! acquire_plugin_lock "$lock_dir" "$timeout"; then
        printf 'write_stage_snapshot: lock timeout (%ss) on %s\n' \
            "$timeout" "$lock_dir" >&2
        return 3
    fi
    _snapshot_writer_cleanup_lock_dir="$lock_dir"
    _snapshot_writer_cleanup_tmp_path="$tmp_path"
    _snapshot_writer_cleanup_body_tmp="$body_tmp"
    _snapshot_writer_cleanup_raw_chunk="$raw_chunk"
    _snapshot_writer_cleanup_fm_probe="$fm_probe_path"
    _snapshot_writer_cleanup_fm_final="$fm_final_path"
    trap '_snapshot_writer_cleanup "$?"' EXIT
    trap '_snapshot_writer_cleanup 130; exit 130' INT
    trap '_snapshot_writer_cleanup 143; exit 143' TERM

    # Symlink T-7 mitigation — if final_path exists as symlink, unlink first.
    if [ -L "$final_path" ]; then
        rm -f "$final_path"
    fi

    # Compose a conservative body-budget probe (size_bytes uses the cap width,
    # truncated=true). The exact final frontmatter is solved below; byte counts
    # use wc -c because ${#var} would undercount UTF-8 option strings and the
    # truncation marker.
    local fm_bytes body_bytes max_body marker_bytes
    _snapshot_render_frontmatter \
        "$task_id" "$stage" "$command" "$captured_at" "$captured_by" \
        "$recommended_next" "$options_file" "$SNAPSHOT_MAX_BYTES" "true" \
        > "$fm_probe_path"
    fm_bytes="$(wc -c < "$fm_probe_path" | tr -d ' ')"
    body_bytes="$(wc -c < "$body_file" | tr -d ' ')"
    marker_bytes="$(printf '%s' "$SNAPSHOT_TRUNCATION_MARKER" | wc -c | tr -d ' ')"

    local truncated="false"
    # Reserve frontmatter + marker + leading newline + trailing newline.
    max_body=$(( SNAPSHOT_MAX_BYTES - fm_bytes - marker_bytes - 2 ))
    if [ "$max_body" -lt 0 ]; then
        max_body=0
    fi

    if [ "$body_bytes" -gt "$max_body" ]; then
        # Keep first $max_body bytes, then strip any trailing partial UTF-8
        # codepoint via `iconv -c` (POSIX; macOS libiconv + Linux glibc).
        # `head -c` is byte-accurate but codepoint-ignorant: a cut landing
        # mid-sequence yields invalid UTF-8 (TUNE-0254 F5 from /dr-verify).
        # `iconv -c` drops invalid/incomplete sequences; final size may shrink
        # by up to 3 bytes (max codepoint length - 1) below the nominal
        # max_body, which is well within the SNAPSHOT_MAX_BYTES cap.
        # macOS libiconv exits 1 + writes a stderr warning on incomplete
        # trailing sequences (the very case we are normalising), so we
        # absorb the exit code with `|| true` and silence stderr.
        # `head -c 0` is NOT portable: GNU coreutils accepts it and emits
        # nothing, BSD/macOS head rejects it with "illegal byte count -- 0"
        # and exits 1. max_body is legitimately clamped to 0 above when the
        # frontmatter alone consumes the whole cap (oversized --options-file),
        # so this path IS reachable — and on macOS it aborted the writer
        # before the cap check could fail closed, turning a hard guard into a
        # silent pass. Linux-only CI never saw it.
        if [ "$max_body" -eq 0 ]; then
            : > "$raw_chunk"
        else
            head -c "$max_body" "$body_file" > "$raw_chunk"
        fi
        iconv -c -f UTF-8 -t UTF-8 "$raw_chunk" > "$body_tmp" 2>/dev/null || true
        rm -f "$raw_chunk"
        printf '\n%s\n' "$SNAPSHOT_TRUNCATION_MARKER" >> "$body_tmp"
        truncated="true"
    else
        cp "$body_file" "$body_tmp"
    fi

    local final_body_bytes size_bytes actual_size
    final_body_bytes="$(wc -c < "$body_tmp" | tr -d ' ')"
    if ! size_bytes="$(_snapshot_render_exact_frontmatter \
        "$task_id" "$stage" "$command" "$captured_at" "$captured_by" \
        "$recommended_next" "$options_file" "$final_body_bytes" \
        "$(( fm_bytes + final_body_bytes ))" "$truncated" "$fm_final_path")"; then
        _snapshot_writer_cleanup 0
        return 1
    fi

    if [ "$size_bytes" -gt "$SNAPSHOT_MAX_BYTES" ]; then
        printf 'write_stage_snapshot: rendered snapshot is %s bytes; exceeds %s-byte cap\n' \
            "$size_bytes" "$SNAPSHOT_MAX_BYTES" >&2
        _snapshot_writer_cleanup 0
        return 1
    fi

    {
        cat "$fm_final_path"
        cat "$body_tmp"
    } > "$tmp_path"

    # Verify the actual composed artifact before the atomic publish. This is
    # the final enforcement point for options/frontmatter as well as body.
    actual_size="$(wc -c < "$tmp_path" | tr -d ' ')"
    if [ "$actual_size" -ne "$size_bytes" ]; then
        printf 'write_stage_snapshot: composed size %s differs from declared size %s\n' \
            "$actual_size" "$size_bytes" >&2
        _snapshot_writer_cleanup 0
        return 1
    fi
    if [ "$actual_size" -gt "$SNAPSHOT_MAX_BYTES" ]; then
        printf 'write_stage_snapshot: rendered snapshot is %s bytes; exceeds %s-byte cap\n' \
            "$actual_size" "$SNAPSHOT_MAX_BYTES" >&2
        _snapshot_writer_cleanup 0
        return 1
    fi

    chmod 600 "$tmp_path" 2>/dev/null || true

    # fsync via dd (POSIX-portable; Python fallback if dd lacks conv=fsync).
    if ! dd if="$tmp_path" of="$tmp_path" conv=notrunc,fsync count=0 \
        2>/dev/null; then
        # Older dd without conv=fsync — skip; mv still atomic on POSIX.
        :
    fi

    # Atomic rename. -T (no-target-directory) on GNU mv; macOS default mv is
    # safe-on-overwrite for regular files. Pre-unlink symlink already handled.
    mv -f "$tmp_path" "$final_path"

    # Harness journal hook — auto-detect /tmp/datarim-test-{task_id}.
    # If the operator initialised the test harness for this TASK-ID
    # via dev-tools/datarim-stage-probe-init.sh, append one journal line
    # per writer call. Fail-soft per V-AC-7 contract — never abort snapshot.
    # Detection heuristics: header-present = body_file first line matches
    # ^**{task_id} · ; cta-footer = body contains Cyrillic CTA marker
    # or /dr-* {task_id} primary line.
    local journal_dir="/tmp/datarim-test-${task_id}"
    if [ -d "$journal_dir" ] && [ ! -L "$journal_dir" ]; then
        local _first _hdr_y _cta_y _sha
        _first="$(head -1 "$body_file" 2>/dev/null || true)"
        if printf '%s\n' "$_first" | grep -qE "^\\*\\*${task_id} · "; then
            _hdr_y=y
        else
            _hdr_y=n
        fi
        if grep -qE "Следующий шаг — ${task_id}|/dr-[a-z]+ ${task_id}|primary CTA" \
                "$body_file" 2>/dev/null; then
            _cta_y=y
        else
            _cta_y=n
        fi
        _sha="$(shasum -a 256 "$final_path" 2>/dev/null \
            | awk '{print substr($1,1,12)}' || echo "------------")"
        {
            printf '%s · %s · header-present:%s · snapshot-written:y · cta-footer:%s · snapshot-sha:%s\n' \
                "$stage" "$captured_at" "$_hdr_y" "$_cta_y" "$_sha"
        } >> "${journal_dir}/journal.md" 2>/dev/null || true
    fi

    _snapshot_writer_cleanup 0
    return 0
}

# If sourced, expose write_stage_snapshot. If invoked directly, dispatch.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    write_stage_snapshot "$@"
fi
