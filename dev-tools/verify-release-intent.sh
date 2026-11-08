#!/usr/bin/env bash
# Short post-publication verification: tag exists, is annotated, and points at
# the durable release-intent source SHA. Publication (creating the tag /
# GitHub Release) is a separate step; this script only verifies.
#
# Usage:
#   verify-release-intent.sh --check [--repo <path>] [--intent-file PATH] [--report]
set -euo pipefail

repo="." ; mode="" ; report=false ; intent_file=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check) mode=check; shift ;;
        --repo) repo="${2:-}"; shift 2 ;;
        --intent-file) intent_file="${2:-}"; shift 2 ;;
        --report) report=true; shift ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ "$mode" = check ] || { echo "ERROR: --check is required" >&2; exit 2; }
git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "ERROR: --repo '$repo' is not a git work tree" >&2
    exit 2
}
[ -n "$intent_file" ] || intent_file="$repo/.datarim/release-intent.json"
[ -f "$intent_file" ] || {
    echo "FAIL: no release intent at $intent_file" >&2
    exit 1
}

# Assign via mapfile/command substitution so shellcheck sees the bindings (SC2154).
mapfile -t _intent_fields < <(python3 - "$intent_file" <<'PY'
import json
import sys
from pathlib import Path
intent = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if intent.get("schema") != "ReleaseIntent/v1":
    raise SystemExit("ERROR: unsupported intent schema")
print(intent["version"])
print(intent["source_sha"])
PY
)
version="${_intent_fields[0]:-}"
source_sha="${_intent_fields[1]:-}"
[ -n "$version" ] || { echo "ERROR: intent missing version" >&2; exit 2; }
[ -n "$source_sha" ] || { echo "ERROR: intent missing source_sha" >&2; exit 2; }

tag_ref="refs/tags/v${version}"
remote="$(git -C "$repo" ls-remote --tags origin "$tag_ref" "${tag_ref}^{}" 2>/dev/null || true)"
[ -n "$remote" ] || {
    echo "FAIL: intent for v${version} has no remote tag yet" >&2
    exit 1
}
# Annotated tag: peeled object must exist.
peeled="$(printf '%s\n' "$remote" | awk -v ref="${tag_ref}^{}" '$2 == ref { print $1 }')"
[ -n "$peeled" ] || {
    echo "FAIL: remote tag v${version} is not annotated" >&2
    exit 1
}
[ "$peeled" = "$source_sha" ] || {
    echo "FAIL: tag v${version} points at ${peeled}, intent source_sha=${source_sha}" >&2
    exit 1
}

# Signature check when ssh allowed-signers is present; otherwise NOT_MEASURED.
signers="$repo/.github/ssh-signing-allowed-signers"
if [ -f "$signers" ] && [ -x "$repo/dev-tools/verify-release-tag.sh" ]; then
    if bash "$repo/dev-tools/verify-release-tag.sh" verify --repo "$repo" --tag "v${version}" \
        --allowed-signers "$signers" >/tmp/verify-release-intent.out 2>&1; then
        echo "PASS: tag v${version} matches intent source_sha=${source_sha} and signature verified"
        exit 0
    fi
    echo "FAIL: tag signature verification failed for v${version}" >&2
    [ "$report" = true ] && cat /tmp/verify-release-intent.out >&2 || true
    exit 1
fi

echo "PASS: tag v${version} matches intent source_sha=${source_sha}; signature=NOT_MEASURED (no allowed-signers/verify helper in this checkout)"
exit 0
