#!/usr/bin/env bash
# Record a durable release intent (version + source SHA) so tag arrival can be
# reconciled off the runner instead of holding a CI job in a sleep loop.
#
# Usage:
#   record-release-intent.sh --repo <path> --version X.Y.Z --source-sha <40hex>
#   record-release-intent.sh --repo <path> --from-head
set -euo pipefail

repo="." ; version="" ; source_sha="" ; from_head=false
while [ $# -gt 0 ]; do
    case "$1" in
        --repo) repo="${2:-}"; shift 2 ;;
        --version) version="${2:-}"; shift 2 ;;
        --source-sha) source_sha="${2:-}"; shift 2 ;;
        --from-head) from_head=true; shift ;;
        -h|--help)
            sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    esac
done

git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "ERROR: --repo '$repo' is not a git work tree" >&2
    exit 2
}

if [ "$from_head" = true ]; then
    [ -f "$repo/VERSION" ] || { echo "ERROR: $repo/VERSION not found" >&2; exit 2; }
    version="$(tr -d ' \t\n' < "$repo/VERSION")"
    source_sha="$(git -C "$repo" rev-parse HEAD)"
fi

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "ERROR: version '$version' is not X.Y.Z" >&2
    exit 2
}
[[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] || {
    echo "ERROR: source-sha must be a 40-char lowercase hex SHA" >&2
    exit 2
}

intent_dir="$repo/.datarim"
mkdir -p "$intent_dir"
intent_path="$intent_dir/release-intent.json"
recorded_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
python3 - "$intent_path" "$version" "$source_sha" "$recorded_at" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = {
    "schema": "ReleaseIntent/v1",
    "version": sys.argv[2],
    "source_sha": sys.argv[3],
    "recorded_at": sys.argv[4],
    "tag": f"v{sys.argv[2]}",
    "notes": [
        "Durable release intent for off-runner tag reconcile.",
        "GITHUB_TOKEN-created tag events do not trigger workflows; prefer schedule or a non-GITHUB_TOKEN tag push.",
    ],
}
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print(f"recorded {path} version={payload['version']} source_sha={payload['source_sha']}")
PY
