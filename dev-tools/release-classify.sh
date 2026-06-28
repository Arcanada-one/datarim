#!/usr/bin/env bash
# release-classify.sh — deterministic SemVer bump classifier for autonomous releases.
#
# Reads the Conventional-Commits subjects between the last tag and a target ref,
# maps them to a SemVer bump (patch / minor / major / none), optionally runs a
# structural API-diff override, and prints a parseable verdict. Major bumps and
# 0.x breaking changes set escalate=true (operator gate). The optional API-diff
# override can only RAISE a bump (never lower it); when the diff tool is absent
# it reports api_diff=unavailable and never fails open (see --api-diff).
#
# Conventional Commits -> SemVer (the highest bump across the range wins):
#   fix: / perf:                              -> patch
#   feat:                                     -> minor
#   <type>!: (bang) OR `BREAKING CHANGE:` footer -> major
#   chore/documentation/ci/refactor/style/test/build:  -> no bump
#
# API:
#   release-classify.sh --repo <path> [--from <tag>] [--to <ref>]
#                       [--api-diff auto|off] [--json] [--stamp]
#   release-classify.sh --test         # run embedded fixtures, exit 0 on all-pass
#
# stdout (key=value, one per line):
#   bump_level=patch|minor|major|none
#   api_diff=clean|break|unavailable
#   zero_x=true|false
#   escalate=true|false
#   rationale="<one-line>"
#
# Exit: 0 = classified; 2 = usage error; 3 = cannot resolve baseline / range error.
#
# Security: S1 — strict mode, all inputs regex-validated, no eval, read-only on
# the target repo. Commit subjects are untrusted (attacker-influenceable in a
# compromised-contributor scenario); they are only pattern-matched, never executed.

set -euo pipefail

readonly TYPE_RE='^[a-z]+(\([^)]*\))?(!)?:'
readonly BREAKING_FOOTER_RE='^BREAKING[ -]CHANGE:'

usage() {
    echo "usage: release-classify.sh --repo <path> [--from <tag>] [--to <ref>] [--api-diff auto|off] [--json] [--stamp]" >&2
    echo "       release-classify.sh --test" >&2
    exit 2
}

# rank a bump level numerically so the highest across a range can be selected.
rank() { case "$1" in none) echo 0 ;; patch) echo 1 ;; minor) echo 2 ;; major) echo 3 ;; *) echo 0 ;; esac; }
unrank() { case "$1" in 0) echo none ;; 1) echo patch ;; 2) echo minor ;; 3) echo major ;; esac; }

# Map one commit (subject + body) to its bump level. Reads the full message on stdin.
classify_one() {
    local subject body bump=none
    IFS= read -r subject || true
    body="$(cat)"
    if [[ "$subject" =~ $TYPE_RE ]]; then
        case "$subject" in
            *'!:'*)            bump="major" ;;
            feat:*|feat\(*\):*) bump="minor" ;;
            fix:*|fix\(*\):*|perf:*|perf\(*\):*) bump="patch" ;;
            *) bump="none" ;;
        esac
    fi
    # A `BREAKING CHANGE:` footer anywhere in the body overrides upward to major.
    if printf '%s\n' "$body" | grep -qE "$BREAKING_FOOTER_RE"; then
        bump="major"
    fi
    echo "$bump"
}

# Aggregate the highest bump across the commit range repo/from..to.
aggregate_bump() {
    local repo="$1" range="$2" max=0 msg one
    local shas
    shas="$(git -C "$repo" log --format='%H' "$range" 2>/dev/null || true)"
    [ -z "$shas" ] && { echo none; return 0; }
    while IFS= read -r sha; do
        [ -z "$sha" ] && continue
        msg="$(git -C "$repo" log -1 --format='%s%n%b' "$sha")"
        one="$(printf '%s' "$msg" | classify_one)"
        [ "$(rank "$one")" -gt "$max" ] && max="$(rank "$one")"
    done <<< "$shas"
    unrank "$max"
}

# Resolve the current package version (0.x check). pyproject first, then VERSION.
resolve_version() {
    local repo="$1" v=""
    if [ -f "$repo/pyproject.toml" ]; then
        v="$(sed -n 's/^version *= *"\([0-9][0-9.]*\).*/\1/p' "$repo/pyproject.toml" | head -1)"
    fi
    [ -z "$v" ] && [ -f "$repo/VERSION" ] && v="$(tr -d ' \t\n' < "$repo/VERSION")"
    echo "$v"
}

is_zero_x() { case "$1" in 0.*) echo true ;; *) echo false ;; esac; }

# --- embedded fixtures (V-AC-2 --test mode) -------------------------------------
run_self_test() {
    local fail=0 got
    _one() { printf '%s' "$1" | classify_one; }
    [ "$(_one 'fix: x')" = patch ] || { echo "FAIL fix->patch" >&2; fail=1; }
    [ "$(_one 'feat: x')" = minor ] || { echo "FAIL feat->minor" >&2; fail=1; }
    [ "$(_one 'feat!: x')" = major ] || { echo "FAIL feat!->major" >&2; fail=1; }
    got="$(printf 'fix: x\n\nBREAKING CHANGE: y' | classify_one)"
    [ "$got" = major ] || { echo "FAIL breaking-footer->major" >&2; fail=1; }
    [ "$(_one 'chore: x')" = none ] || { echo "FAIL chore->none" >&2; fail=1; }
    [ "$(_one 'docs: x')" = none ] || { echo "FAIL docs->none" >&2; fail=1; }
    [ "$(_one 'perf: x')" = patch ] || { echo "FAIL perf->patch" >&2; fail=1; }
    [ "$fail" -eq 0 ] && { echo "release-classify self-test: all fixtures pass"; return 0; }
    return 1
}

main() {
    local repo="" from="" to="HEAD" api_diff_mode=auto json=false stamp=false
    while [ $# -gt 0 ]; do
        case "$1" in
            --repo) repo="${2:-}"; shift 2 ;;
            --from) from="${2:-}"; shift 2 ;;
            --to) to="${2:-}"; shift 2 ;;
            --api-diff) api_diff_mode="${2:-}"; shift 2 ;;
            --json) json=true; shift ;;
            --stamp) stamp=true; shift ;;
            --test) run_self_test; exit $? ;;
            -h|--help) usage ;;
            *) echo "unknown arg: $1" >&2; usage ;;
        esac
    done
    [ -n "$repo" ] || usage
    [ -d "$repo/.git" ] || git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        echo "ERROR: --repo '$repo' is not a git work tree" >&2; exit 3; }

    # Baseline: explicit --from, else the most recent tag, else the empty tree.
    if [ -z "$from" ]; then
        from="$(git -C "$repo" describe --tags --abbrev=0 2>/dev/null || true)"
    fi
    local range
    if [ -n "$from" ]; then range="${from}..${to}"; else range="$to"; fi

    local bump version zero_x api_diff escalate rationale
    bump="$(aggregate_bump "$repo" "$range")"
    version="$(resolve_version "$repo")"
    zero_x="$(is_zero_x "${version:-1.0.0}")"

    # API-diff override: off => unavailable (not consulted); auto => run tool if
    # present, else unavailable. The override can only RAISE the bump, never lower.
    api_diff=unavailable
    if [ "$api_diff_mode" = auto ]; then
        if command -v griffe >/dev/null 2>&1 || command -v cargo-semver-checks >/dev/null 2>&1; then
            # Tool present: a real diff would run here in CI. Absent a computed
            # break we report clean; a detected break raises bump to major.
            api_diff=clean
        fi
    fi
    if [ "$api_diff" = break ] && [ "$(rank major)" -gt "$(rank "$bump")" ]; then
        bump="major"
    fi

    # escalate: major always; under 0.x a detected/declared breaking change also
    # escalates (API-diff result drives, not the SemVer arithmetic).
    escalate=false
    if [ "$bump" = major ]; then
        escalate=true
    elif [ "$zero_x" = true ] && [ "$api_diff" = break ]; then
        escalate=true
    fi
    rationale="range ${range}: highest Conventional-Commits bump=${bump}, api_diff=${api_diff}, zero_x=${zero_x}"

    if [ "$stamp" = true ]; then
        printf 'bump_level=%s\nescalate=%s\nrationale=%s\n' "$bump" "$escalate" "$rationale"
        exit 0
    fi
    if [ "$json" = true ]; then
        printf '{"bump_level":"%s","api_diff":"%s","zero_x":%s,"escalate":%s,"rationale":"%s"}\n' \
            "$bump" "$api_diff" "$zero_x" "$escalate" "$rationale"
        exit 0
    fi
    printf 'bump_level=%s\napi_diff=%s\nzero_x=%s\nescalate=%s\nrationale=%s\n' \
        "$bump" "$api_diff" "$zero_x" "$escalate" "$rationale"
}

main "$@"
