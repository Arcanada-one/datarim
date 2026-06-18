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

readonly SNAPSHOT_TASK_ID_RE='^[A-Z]{2,10}-[0-9]{4}(-[A-Za-z0-9]+)*$'
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

    mkdir -p "$snapshots_dir"
    chmod 700 "$snapshots_dir" 2>/dev/null || true

    local timeout="${DR_SNAPSHOT_LOCK_TIMEOUT:-60}"
    if ! acquire_plugin_lock "$lock_dir" "$timeout"; then
        printf 'write_stage_snapshot: lock timeout (%ss) on %s\n' \
            "$timeout" "$lock_dir" >&2
        return 3
    fi
    # shellcheck disable=SC2064  # expand task_id NOW for the trap
    trap "release_plugin_lock \"$lock_dir\"; rm -f \"$tmp_path\"" EXIT INT TERM

    # Symlink T-7 mitigation — if final_path exists as symlink, unlink first.
    if [ -L "$final_path" ]; then
        rm -f "$final_path"
    fi

    # Compose a worst-case frontmatter probe (size_bytes uses the cap width,
    # truncated=true) so the real frontmatter is never longer. Byte counts use
    # wc -c — ${#var} counts characters and would undercount UTF-8 content
    # (option strings, the truncation marker itself).
    local fm_probe fm_bytes body_bytes max_body marker_bytes fm_final
    fm_probe="$(_snapshot_render_frontmatter \
        "$task_id" "$stage" "$command" "$captured_at" "$captured_by" \
        "$recommended_next" "$options_file" "$SNAPSHOT_MAX_BYTES" "true")"
    fm_bytes="$(printf '%s' "$fm_probe" | wc -c | tr -d ' ')"
    body_bytes="$(wc -c < "$body_file" | tr -d ' ')"
    marker_bytes="$(printf '%s' "$SNAPSHOT_TRUNCATION_MARKER" | wc -c | tr -d ' ')"

    local truncated="false"
    # Reserve frontmatter + marker + leading newline + trailing newline.
    max_body=$(( SNAPSHOT_MAX_BYTES - fm_bytes - marker_bytes - 2 ))
    if [ "$max_body" -lt 0 ]; then
        max_body=0
    fi

    local body_tmp="${tmp_path}.body"
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
        local raw_chunk="${body_tmp}.raw"
        head -c "$max_body" "$body_file" > "$raw_chunk"
        iconv -c -f UTF-8 -t UTF-8 "$raw_chunk" > "$body_tmp" 2>/dev/null || true
        rm -f "$raw_chunk"
        printf '\n%s\n' "$SNAPSHOT_TRUNCATION_MARKER" >> "$body_tmp"
        truncated="true"
    else
        cp "$body_file" "$body_tmp"
    fi

    local final_body_bytes
    final_body_bytes="$(wc -c < "$body_tmp" | tr -d ' ')"
    local size_bytes=$(( fm_bytes + final_body_bytes ))

    fm_final="$(_snapshot_render_frontmatter \
        "$task_id" "$stage" "$command" "$captured_at" "$captured_by" \
        "$recommended_next" "$options_file" "$size_bytes" "$truncated")"

    {
        printf '%s' "$fm_final"
        cat "$body_tmp"
    } > "$tmp_path"
    rm -f "$body_tmp"

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

    release_plugin_lock "$lock_dir"
    trap - EXIT INT TERM
    return 0
}

# If sourced, expose write_stage_snapshot. If invoked directly, dispatch.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    write_stage_snapshot "$@"
fi
