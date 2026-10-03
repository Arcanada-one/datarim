#!/usr/bin/env bash
# adapters/dr-dream-adapter.sh — emit eval-dataset records from /dr-dream reflections.
#
# Reads reflection-*.md files in the directory passed as argv[1] and emits one
# JSONL record per gap signal (source-adapter-contract.md). A gap signal is a
# bullet line under a reflection that names a weakness:
#   "- gap: ..."  /  "- weakness: ..."  /  "- improvement: ..."
# Every gap maps to outcome "failure" (it marks where the skill fell short).
# JSON is emitted via jsonl_emit_record (jq) for correct escaping.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/jsonl.sh
source "$SCRIPT_DIR/../lib/jsonl.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") <reflection-dir>

Emit JSONL eval-dataset records (one per gap signal) to stdout.
Exit 0 on success (empty stdout if no gaps); exit 2 on usage error.
EOF
}

_fm_scalar() {
    local file=$1 key=$2
    sed -n '/^---$/,/^---$/p' "$file" \
        | grep -E "^${key}:" \
        | head -n1 \
        | sed -E "s/^${key}:[[:space:]]*//; s/^\"(.*)\"$/\1/; s/[[:space:]]+$//"
}

main() {
    case "${1:-}" in
        -h|--help) usage; exit 0 ;;
        "") usage >&2; exit 2 ;;
    esac
    local dir=$1
    [ -d "$dir" ] || { echo "dr-dream-adapter: not a directory: $dir" >&2; exit 1; }
    jsonl_require_jq || exit 3

    local file id signal kind text
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        id=$(_fm_scalar "$file" id)
        # Each gap/weakness/improvement bullet becomes one record.
        while IFS= read -r signal; do
            [ -n "$signal" ] || continue
            # signal looks like "- gap: <text>"; split kind and text.
            kind=$(printf '%s' "$signal" | sed -E 's/^[[:space:]]*-[[:space:]]*([a-z]+):.*/\1/')
            text=$(printf '%s' "$signal" | sed -E 's/^[[:space:]]*-[[:space:]]*[a-z]+:[[:space:]]*//')
            jsonl_emit_record \
                "${id}: ${kind}" \
                "" \
                "$text" \
                "failure" \
                "dr-dream"
        done < <(grep -E '^[[:space:]]*-[[:space:]]*(gap|weakness|improvement):' "$file")
    done < <(find "$dir" -maxdepth 1 -type f -name 'reflection-*.md' | sort)
}

main "$@"
