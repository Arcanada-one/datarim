#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
manifest="${repo_root}/datarim/insights/TALO-0001-research-authority-audit.json"
consumer=${TALO_RESEARCH_CONSUMER:-${repo_root}/dev-tools/check-talo-0001-research-authority.sh}
knowledge_root=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --knowledge-root)
            [ "$#" -ge 2 ] || { echo "ERROR: --knowledge-root requires a path" >&2; exit 2; }
            knowledge_root=$2
            shift 2
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

for command in git gh jq curl; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: $command" >&2
        exit 2
    }
done

snapshot=$(jq -er '.knowledge_snapshot' "$manifest")
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT

if [ -z "$knowledge_root" ]; then
    knowledge_root="${scratch}/talomnia-knowledge"
    gh repo clone Arcanada-one/talomnia-knowledge "$knowledge_root" \
        -- --filter=blob:none --no-checkout --quiet
    git -C "$knowledge_root" fetch --quiet --depth=1 origin "$snapshot"
    git -C "$knowledge_root" checkout --quiet --detach "$snapshot"
fi

actual_snapshot=$(git -C "$knowledge_root" rev-parse HEAD)
if [ "$actual_snapshot" != "$snapshot" ]; then
    echo "ERROR: knowledge snapshot mismatch: expected=$snapshot actual=$actual_snapshot" >&2
    exit 1
fi

comment_dir="${scratch}/comments"
cache_dir="${scratch}/external-cache"
mkdir -p "$comment_dir" "$cache_dir"

for comment_id in 5347868439 5347971637; do
    gh api "repos/Arcanada-one/talomnia-trace/issues/comments/${comment_id}" \
        >"${comment_dir}/${comment_id}.json"
done

while IFS=$'\t' read -r source_id repository commit source_path; do
    curl --fail --silent --show-error --location \
        --max-time 20 --max-filesize 16777216 --proto '=https' \
        "https://raw.githubusercontent.com/${repository}/${commit}/${source_path}" \
        --output "${cache_dir}/${source_id}.body"
done < <(
    jq -er '.external_pins[] | [.source_id,.repository,.commit,.path] | @tsv' \
        "$manifest"
)

"$consumer" \
    --knowledge-root "$knowledge_root" \
    --comment-json "5347868439=${comment_dir}/5347868439.json" \
    --comment-json "5347971637=${comment_dir}/5347971637.json" \
    --external-cache-dir "$cache_dir" \
    --verify-external-remote
