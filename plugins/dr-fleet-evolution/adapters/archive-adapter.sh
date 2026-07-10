#!/usr/bin/env bash
# adapters/archive-adapter.sh — emit eval-dataset records from task archives.
#
# Reads archive-*.md files in the directory passed as argv[1] and emits one
# JSONL record per archive (source-adapter-contract.md). Two archive formats
# are supported (qa-report-TUNE-0380 finding #1: ~40% of archives predate the
# YAML-frontmatter convention):
#
#   YAML-frontmatter — id/status/verification_outcome read from the block
#   between the first two '---' lines. outcome is derived:
#     success  — status: completed AND (n_a: true OR missed_by_verify == 0)
#     failure  — anything else (missed regressions, non-completed status)
#
#   prose-header — no frontmatter; the first markdown heading line carries
#   the TASK-ID (and, best-effort, a title), and a bold-prose `**Status:**`
#   line anywhere in the file carries completion state. outcome is derived:
#     success  — status text contains "complet" (covers "Completed",
#                "completed", "✅ Completed")
#     failure  — anything else
#
# Frontmatter/heading text is parsed with sed/grep (no yq dependency — yq is
# absent on the default CI runner). JSON is emitted via jsonl_emit_record
# (jq) for correct escaping.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/jsonl.sh
source "$SCRIPT_DIR/../lib/jsonl.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <archive-dir>

Emit JSONL eval-dataset records (one per archive-*.md) to stdout.
Exit 0 on success (empty stdout if no archives); exit 2 on usage error.
EOF
}

# Extract a top-level scalar frontmatter field (first match) from a file.
# Frontmatter is the block between the first two '---' lines.
_fm_scalar() {
    local file=$1 key=$2
    sed -n '/^---$/,/^---$/p' "$file" \
        | grep -E "^${key}:" \
        | head -n1 \
        | sed -E "s/^${key}:[[:space:]]*//; s/^\"(.*)\"$/\1/; s/[[:space:]]+$//"
}

# Extract a nested scalar under verification_outcome (2-space indent).
_fm_vo() {
    local file=$1 key=$2
    sed -n '/^---$/,/^---$/p' "$file" \
        | grep -E "^[[:space:]]{2}${key}:" \
        | head -n1 \
        | sed -E "s/^[[:space:]]+${key}:[[:space:]]*//; s/[[:space:]]+$//"
}

# true if the file uses the YAML-frontmatter convention (first line is '---').
_has_frontmatter() {
    [ "$(sed -n '1p' "$1")" = "---" ]
}

# TASK-ID from a prose archive's first heading line (e.g.
# "# Archive: TUNE-0012 — title", "# Archive -- TUNE-0183: title",
# "# Archive — TUNE-0010: title", "# TUNE-0052 — title").
_prose_id() {
    sed -n '1p' "$1" | grep -oE '[A-Z][A-Z0-9]*-[0-9]+' | head -n1
}

# Best-effort title: text on the heading line after the TASK-ID and its
# separator punctuation. Falls back to empty (never fatal — task_input, not
# title, is the eval-dataset key).
_prose_title() {
    local file=$1 id
    id=$(_prose_id "$file")
    [ -n "$id" ] || return 0
    sed -n '1p' "$file" | sed -E "s/^.*${id}[[:space:]]*[:—-]+[[:space:]]*//"
}

# First `**Status:**` bold-prose line anywhere in the file (not confined to a
# frontmatter block, since prose archives have none).
_prose_status() {
    grep -m1 -E '^\*\*Status:\*\*' "$1" \
        | sed -E 's/^\*\*Status:\*\*[[:space:]]*//; s/[[:space:]]+$//'
}

archive_outcome() {
    local file=$1
    if _has_frontmatter "$file"; then
        local status n_a missed
        status=$(_fm_scalar "$file" status)
        n_a=$(_fm_vo "$file" n_a)
        missed=$(_fm_vo "$file" missed_by_verify)
        if [ "$status" = "completed" ] && { [ "$n_a" = "true" ] || [ "${missed:-0}" = "0" ]; }; then
            echo "success"
        else
            echo "failure"
        fi
    else
        local status
        status=$(_prose_status "$file")
        if printf '%s' "${status,,}" | grep -q 'complet'; then
            echo "success"
        else
            echo "failure"
        fi
    fi
}

main() {
    case "${1:-}" in
        -h|--help) usage; exit 0 ;;
        "") usage >&2; exit 2 ;;
    esac
    local dir=$1
    [ -d "$dir" ] || { echo "archive-adapter: not a directory: $dir" >&2; exit 1; }
    jsonl_require_jq || exit 3

    local file id title outcome
    # Stable order for reproducible datasets.
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        if _has_frontmatter "$file"; then
            id=$(_fm_scalar "$file" id)
            title=$(_fm_scalar "$file" title)
        else
            id=$(_prose_id "$file")
            title=$(_prose_title "$file")
        fi
        outcome=$(archive_outcome "$file")
        jsonl_emit_record \
            "$id" \
            "$title" \
            "outcome=$outcome (archive $(basename "$file"))" \
            "$outcome" \
            "archive"
    done < <(find "$dir" -maxdepth 1 -type f -name 'archive-*.md' | sort)
}

main "$@"
