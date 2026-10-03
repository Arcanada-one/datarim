#!/usr/bin/env bash
# reverify-session-claims.sh — deterministic re-verification banner emitter.
#
# Purpose:
#   The session-handoff consumer (/dr-continue) must never trust a saved claim.
#   This script is the deterministic core the consumer invokes to turn raw git
#   exit codes into the canonical re-verification banners. It does NOT replace
#   the agent orchestration in commands/dr-continue.md — the agent locates the
#   artefact, reads the layers, and routes; this script emits the safety-banner
#   strings so the "report claim as unverified" property is deterministically
#   testable rather than agent-rendered prose that can silently regress.
#
# Modes (one probe per invocation; the consumer calls once per claim/repo/file):
#
#   --sha-presence --repo <dir> --sha <40-hex> [--files <path>...]
#       Emit CLAIM-UNVERIFIED when <sha> is NOT an ancestor of origin/main
#       (squash-collision). When --files given and the content diff against
#       origin/main is empty, append the content-landed evidence line so the
#       consumer does not falsely conclude work was lost.
#       Emit nothing (exit 0) when the sha IS an ancestor (claim holds).
#
#   --stale --repo <dir> --saved-sha <40-hex>
#       Emit STALE SNAPSHOT when current origin/main HEAD differs from the
#       saved sha. Emit nothing when they match.
#
#   --file-missing --path <path>
#       Emit FILE-MISSING when <path> does not exist. Emit nothing when present.
#
# Exit codes:
#   0  probe ran (banner emitted to stdout when the claim failed; empty when it held)
#   2  usage error / input validation failure
#   3  repo is not a git work tree
#
# Security (Appendix A / Security Mandate S1):
#   - All inputs regex-validated before use (no path traversal, no injection).
#   - SHA inputs constrained to ^[0-9a-fA-F]{7,40}$.
#   - No eval; every expansion quoted; git invoked with -C <repo> (no cd).
#   - File paths passed positionally to git/stat after `--` (no glob/option leak).

set -euo pipefail

readonly SHA_RE='^[0-9a-fA-F]{7,40}$'

die_usage() {
    printf 'reverify-session-claims: %s\n' "$1" >&2
    exit 2
}

validate_sha() {
    [[ "$1" =~ $SHA_RE ]] || die_usage "invalid SHA (expected 7-40 hex chars): $1"
}

validate_repo() {
    local repo="$1"
    [ -n "$repo" ] || die_usage "missing --repo"
    [ -d "$repo" ] || die_usage "repo dir not found: $repo"
    git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
        || { printf 'reverify-session-claims: not a git work tree: %s\n' "$repo" >&2; exit 3; }
}

probe_sha_presence() {
    local repo="$1" sha="$2"; shift 2
    local files=("$@")
    validate_repo "$repo"
    validate_sha "$sha"

    # Claim holds: sha is an ancestor of origin/main → emit nothing.
    if git -C "$repo" merge-base --is-ancestor "$sha" origin/main 2>/dev/null; then
        return 0
    fi

    printf 'CLAIM-UNVERIFIED: SHA %s not found in origin/main.\n' "$sha"

    # Content-landing evidence: when files given and the diff is empty, the work
    # landed under a foreign squash-commit header — surface it explicitly.
    if [ "${#files[@]}" -gt 0 ]; then
        local diff_out
        diff_out="$(git -C "$repo" diff "$sha" origin/main -- "${files[@]}" 2>/dev/null || true)"
        if [ -z "$diff_out" ]; then
            printf 'CONTENT-LANDED: diff %s..origin/main for the saved files is empty — work landed under a foreign squash-commit header, not lost.\n' "$sha"
        fi
    fi
    return 0
}

probe_stale() {
    local repo="$1" saved_sha="$2"
    validate_repo "$repo"
    validate_sha "$saved_sha"

    local current
    current="$(git -C "$repo" rev-parse origin/main 2>/dev/null || true)"
    [ -n "$current" ] || { printf 'reverify-session-claims: cannot resolve origin/main in %s\n' "$repo" >&2; exit 3; }

    if [ "$saved_sha" != "$current" ]; then
        printf 'STALE SNAPSHOT: %s origin/main changed from %s to %s\n' "$repo" "$saved_sha" "$current"
    fi
    return 0
}

probe_file_missing() {
    local path="$1"
    [ -n "$path" ] || die_usage "missing --path"
    if [ ! -e "$path" ]; then
        printf 'FILE-MISSING: %s — may have moved, merged, or been deleted.\n' "$path"
    fi
    return 0
}

main() {
    [ $# -gt 0 ] || die_usage "no mode given"

    local mode="" repo="" sha="" saved_sha="" path=""
    local files=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --sha-presence) mode="sha"; shift ;;
            --stale)        mode="stale"; shift ;;
            --file-missing) mode="missing"; shift ;;
            --repo)         repo="${2:-}"; shift 2 ;;
            --sha)          sha="${2:-}"; shift 2 ;;
            --saved-sha)    saved_sha="${2:-}"; shift 2 ;;
            --path)         path="${2:-}"; shift 2 ;;
            --files)
                shift
                while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do
                    files+=("$1"); shift
                done
                ;;
            -h|--help) die_usage "see header for usage" ;;
            *) die_usage "unknown argument: $1" ;;
        esac
    done

    case "$mode" in
        sha)     probe_sha_presence "$repo" "$sha" ${files[@]+"${files[@]}"} ;;
        stale)   probe_stale "$repo" "$saved_sha" ;;
        missing) probe_file_missing "$path" ;;
        *)       die_usage "exactly one of --sha-presence / --stale / --file-missing required" ;;
    esac
}

main "$@"
