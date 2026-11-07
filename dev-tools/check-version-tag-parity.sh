#!/usr/bin/env bash
# check-version-tag-parity.sh — a release that never shipped must not look shipped.
#
# Scope: verifies that the version declared in <repo>/VERSION has a matching
# annotated tag v<VERSION> on the `origin` remote. The failure mode this guards
# against is the silent half-release: a release PR bumps VERSION + CHANGELOG and
# merges, the post-merge tagging step never runs, and from then on the repo
# *looks* released (manifest says X.Y.Z) while no tag, no release workflow, no
# tarball, no SBOM, no signature and no GitHub Release exist.
#
# Contract (per AGENTS.md § Validation Discipline):
#   pure shell; --check mode; exit 0 = PASS, exit 1 = FAIL, exit 2 = usage/setup.
#
# The merge→tag window is legitimate: the tag is created by the operator or the
# release gate minutes after the release PR merges. Prefer a durable release
# intent (`.datarim/release-intent.json`) plus an off-runner reconcile job over
# holding a CI runner in --wait-seconds sleep. --wait-seconds remains for local
# debugging only; CI must not park on it.
#
# Usage:
#   check-version-tag-parity.sh --check [--repo <path>] [--wait-seconds N]
#       [--intent-file PATH] [--allow-pending-intent] [--report]
set -euo pipefail

repo="." ; wait_seconds=0 ; mode="" ; report=false
intent_file="" ; allow_pending_intent=false
while [ $# -gt 0 ]; do
    case "$1" in
        --check) mode=check; shift ;;
        --repo) repo="${2:-}"; shift 2 ;;
        --wait-seconds) wait_seconds="${2:-0}"; shift 2 ;;
        --intent-file) intent_file="${2:-}"; shift 2 ;;
        --allow-pending-intent) allow_pending_intent=true; shift ;;
        --report) report=true; shift ;;
        -h|--help)
            sed -n '2,24p' "$0"; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ "$mode" = check ] || { echo "ERROR: --check is required" >&2; exit 2; }
[[ "$wait_seconds" =~ ^[0-9]+$ ]] || { echo "ERROR: --wait-seconds must be an integer" >&2; exit 2; }
git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: --repo '$repo' is not a git work tree" >&2; exit 2; }
[ -f "$repo/VERSION" ] || { echo "ERROR: $repo/VERSION not found" >&2; exit 2; }

version="$(tr -d ' \t\n' < "$repo/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "ERROR: VERSION content '$version' is not X.Y.Z" >&2; exit 2; }
tag_ref="refs/tags/v${version}"
[ -n "$intent_file" ] || intent_file="$repo/.datarim/release-intent.json"

probe() {
    # ls-remote hits the authoritative remote — a locally created but unpushed
    # tag must NOT pass (the release workflow triggers on the remote push).
    # Output capture, not exit code, decides: empty stdout = tag absent.
    local out
    out="$(git -C "$repo" ls-remote --tags origin "$tag_ref" "${tag_ref}^{}" 2>/dev/null || true)"
    # A lightweight tag is not the annotated release required by this contract.
    printf '%s\n' "$out" | awk -v ref="${tag_ref}^{}" '$2 == ref { found=1 } END { exit !found }'
}

preparation() {
    # This is a separately named preparation condition, never proof of shipment.
    # The pinned baseline must still be published and an ancestor of this
    # non-root checkout. After cutover the unrelated root cannot use the marker.
    local helper baseline baseline_object remote_object target_object
    helper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-history-bootstrap.py"
    [ -f "$repo/.datarim/history-bootstrap.json" ] || return 1
    target_object="$(git -C "$repo" ls-remote --tags origin "$tag_ref" 2>/dev/null)" || return 1
    [ -z "$target_object" ] || return 1
    baseline="$(python3 "$helper" --repo "$repo" --mode preparation 2>/dev/null)" || return 1
    baseline="$(printf '%s\n' "$baseline" | sed -n 's/^baseline_tag=//p')"
    baseline_object="$(git -C "$repo" rev-parse "refs/tags/${baseline}")" || return 1
    remote_object="$(git -C "$repo" ls-remote --tags origin "refs/tags/${baseline}" 2>/dev/null)" || return 1
    [ "$remote_object" = "$(printf '%s\t%s' "$baseline_object" "refs/tags/${baseline}")" ] || return 1
    echo "DEFERRED: VERSION ${version} is verified history-bootstrap preparation; v${version} is not shipped. The parentless cutover must publish its matching tag."
}

pending_intent() {
    # Durable intent covers the merge→tag window without sleeping on a runner.
    # Reconcile remains responsible for proving the tag, signature and source SHA.
    [ "$allow_pending_intent" = true ] || return 1
    [ -f "$intent_file" ] || return 1
    python3 - "$intent_file" "$version" <<'PY'
import json
import sys
from pathlib import Path

intent = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
version = sys.argv[2]
if intent.get("schema") != "ReleaseIntent/v1":
    raise SystemExit(1)
if intent.get("version") != version:
    raise SystemExit(1)
source = intent.get("source_sha") or ""
if not isinstance(source, str) or len(source) != 40:
    raise SystemExit(1)
print(
    f"PENDING: VERSION {version} has durable release intent for source_sha={source}; "
    "tag arrival is reconciled off-runner (event or schedule). "
    "Note: tags created with GITHUB_TOKEN do not trigger workflow push/create events."
)
PY
}

deadline=$(( $(date +%s) + wait_seconds ))
while :; do
    if probe; then
        echo "PASS: VERSION ${version} has matching remote tag v${version}"
        exit 0
    fi
    if preparation; then
        exit 0
    fi
    if pending_intent; then
        exit 0
    fi
    [ "$(date +%s)" -lt "$deadline" ] || break
    sleep 30
done

echo "FAIL: VERSION is ${version} but tag v${version} does not exist on origin — the release was never tagged/shipped (waited ${wait_seconds}s)." >&2
if [ "$report" = true ]; then
    echo "Newest remote tags:" >&2
    git -C "$repo" ls-remote --tags origin 'refs/tags/v*' 2>/dev/null | tail -5 >&2 || true
    echo "Remedy: record a durable intent with dev-tools/record-release-intent.sh, run the release-tag-reconcile workflow, or create the annotated tag per documentation/how-to/ release procedure." >&2
fi
exit 1
