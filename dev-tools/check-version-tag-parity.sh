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
# Contract (per CLAUDE.md § Validation Discipline):
#   pure shell; --check mode; exit 0 = PASS, exit 1 = FAIL, exit 2 = usage/setup.
#
# The merge→tag window is legitimate: the tag is created by the operator or the
# release gate minutes after the release PR merges. --wait-seconds N polls the
# remote for up to N seconds before declaring FAIL, so a CI job on the main-push
# event tolerates the normal window and still fails loudly when the tag never
# arrives.
#
# Usage:
#   check-version-tag-parity.sh --check [--repo <path>] [--wait-seconds N] [--report]
set -euo pipefail

repo="." ; wait_seconds=0 ; mode="" ; report=false
while [ $# -gt 0 ]; do
    case "$1" in
        --check) mode=check; shift ;;
        --repo) repo="${2:-}"; shift 2 ;;
        --wait-seconds) wait_seconds="${2:-0}"; shift 2 ;;
        --report) report=true; shift ;;
        -h|--help)
            sed -n '2,21p' "$0"; exit 0 ;;
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

probe() {
    # ls-remote hits the authoritative remote — a locally created but unpushed
    # tag must NOT pass (the release workflow triggers on the remote push).
    # Output capture, not exit code, decides: empty stdout = tag absent.
    local out
    out="$(git -C "$repo" ls-remote --tags origin "$tag_ref" 2>/dev/null || true)"
    [ -n "$out" ]
}

deadline=$(( $(date +%s) + wait_seconds ))
while :; do
    if probe; then
        echo "PASS: VERSION ${version} has matching remote tag v${version}"
        exit 0
    fi
    [ "$(date +%s)" -lt "$deadline" ] || break
    sleep 30
done

echo "FAIL: VERSION is ${version} but tag v${version} does not exist on origin — the release was never tagged/shipped (waited ${wait_seconds}s)." >&2
if [ "$report" = true ]; then
    echo "Newest remote tags:" >&2
    git -C "$repo" ls-remote --tags origin 'refs/tags/v*' 2>/dev/null | tail -5 >&2 || true
    echo "Remedy: run dev-tools/release-gate.sh (tags + pushes on all-green), or create the annotated tag per documentation/how-to/ release procedure." >&2
fi
exit 1
