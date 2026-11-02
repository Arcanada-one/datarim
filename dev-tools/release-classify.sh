#!/usr/bin/env bash
# release-classify.sh — deterministic SemVer bump classifier for autonomous releases.
#
# Reads Conventional-Commits subjects between the last tag and a target ref,
# then uses exact target VERSION/CHANGELOG declarations only when those subjects
# provide no higher bump. Metadata must agree with both tagged versions and the
# immediate SemVer transition; it is a reviewed declaration, not semantic proof.
# Major bumps and 0.x breaking changes set escalate=true (operator gate). No
# structural API-diff adapter is implemented: auto and off report unavailable.
# A future computed API-diff override may only RAISE a bump, never lower it.
#
# Conventional Commit subjects -> SemVer (highest conventional bump wins):
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
IFS=$'\n\t'

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
    shas="$(git -C "$repo" log --format='%H' "$range")" || return 3
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

# Derive a declared bump from exactly one dated target-version CHANGELOG section.
# Unknown populated categories are ambiguous and therefore fail closed.
release_section_bump() {
    local changelog="$1" version="$2"
    printf '%s\n' "$changelog" | awk -v version="$version" '
        BEGIN { prefix = "## [" version "] — "; in_target = 0; headings = 0; max = 0; ambiguous = 0 }
        function valid_date(date, year, month, day, last_day) {
            if (date !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
            year = substr(date, 1, 4) + 0
            month = substr(date, 6, 2) + 0
            day = substr(date, 9, 2) + 0
            if (year < 1 || month < 1 || month > 12 || day < 1) return 0
            if (month == 2) {
                last_day = 28
                if (year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)) last_day = 29
            } else if (month == 4 || month == 6 || month == 9 || month == 11) {
                last_day = 30
            } else {
                last_day = 31
            }
            return day <= last_day
        }
        /^## / {
            in_target = 0
            category = ""
            if (index($0, prefix) == 1) {
                date = substr($0, length(prefix) + 1)
                if (valid_date(date)) {
                    headings++
                    in_target = 1
                }
            }
            next
        }
        in_target && /^### / { category = substr($0, 5); next }
        in_target && /^[[:space:]]*([-+*]|[0-9]+[.)])[[:space:]]+[^[:space:]]/ {
            if (category == "Added") rank = 2
            else if (category == "Fixed") rank = 1
            else if (category == "Breaking" || category == "Breaking Changes") rank = 3
            else { ambiguous = 1; next }
            if (rank > max) max = rank
        }
        END {
            if (headings != 1 || ambiguous || max == 0) print "none"
            else if (max == 1) print "patch"
            else if (max == 2) print "minor"
            else print "major"
        }
    '
}

# Increment a validated nonnegative decimal component without shell integer
# overflow, so large (but valid) SemVer components still fail/compare safely.
increment_component() {
    local digits="$1" result="" digit carry=1 i
    for ((i=${#digits}-1; i>=0; i--)); do
        digit="${digits:i:1}"
        if [ "$carry" -eq 1 ] && [ "$digit" = 9 ]; then
            result="0${result}"
        else
            result="$((digit + carry))${result}"
            carry=0
        fi
    done
    [ "$carry" -eq 0 ] || result="1${result}"
    printf '%s\n' "$result"
}

# A metadata declaration is usable only when both refs' VERSION files agree
# with their stable tag/version and the exact target changelog declares the
# immediate version transition. No command-line bump override exists.
release_metadata_bump() {
    local repo="$1" from_tag="$2" from_sha="$3" target_sha="$4"
    local from_version from_major from_minor from_patch target_version
    local target_major target_minor target_patch changelog declared expected
    if [[ "$from_tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        from_major="${BASH_REMATCH[1]}"
        from_minor="${BASH_REMATCH[2]}"
        from_patch="${BASH_REMATCH[3]}"
    else
        echo none; return 0
    fi
    from_version="$(git -C "$repo" show "${from_sha}:VERSION" 2>/dev/null)" || { echo none; return 0; }
    [ "$from_version" = "${from_major}.${from_minor}.${from_patch}" ] || { echo none; return 0; }

    target_version="$(git -C "$repo" show "${target_sha}:VERSION" 2>/dev/null)" || { echo none; return 0; }
    if [[ "$target_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        target_major="${BASH_REMATCH[1]}"
        target_minor="${BASH_REMATCH[2]}"
        target_patch="${BASH_REMATCH[3]}"
    else
        echo none; return 0
    fi
    changelog="$(git -C "$repo" show "${target_sha}:CHANGELOG.md" 2>/dev/null)" || { echo none; return 0; }
    declared="$(release_section_bump "$changelog" "$target_version")"
    case "$declared" in
        patch)
            expected="$(increment_component "$from_patch")"
            [[ "$target_major" = "$from_major" && "$target_minor" = "$from_minor" && "$target_patch" = "$expected" ]] || declared=none
            ;;
        minor)
            expected="$(increment_component "$from_minor")"
            [[ "$target_major" = "$from_major" && "$target_minor" = "$expected" && "$target_patch" = 0 ]] || declared=none
            ;;
        major)
            expected="$(increment_component "$from_major")"
            [[ "$target_major" = "$expected" && "$target_minor" = 0 && "$target_patch" = 0 ]] || declared=none
            ;;
        *) declared=none ;;
    esac
    echo "$declared"
}

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
    git -C "$repo" rev-parse --verify "${to}^{commit}" >/dev/null 2>&1 || {
        echo "ERROR: cannot resolve target commit" >&2; exit 3; }
    if [ -n "$from" ]; then
        git -C "$repo" rev-parse --verify "${from}^{commit}" >/dev/null 2>&1 || {
            echo "ERROR: cannot resolve baseline commit" >&2; exit 3; }
    fi
    if [ -n "$from" ]; then range="${from}..${to}"; else range="$to"; fi

    local bump conventional_bump metadata_bump version zero_x api_diff escalate rationale
    bump="$(aggregate_bump "$repo" "$range")" || exit 3
    conventional_bump="$bump"
    metadata_bump=none
    if [ -n "$from" ]; then
        local from_sha target_sha
        from_sha="$(git -C "$repo" rev-parse --verify "${from}^{commit}")"
        target_sha="$(git -C "$repo" rev-parse --verify "${to}^{commit}")"
        metadata_bump="$(release_metadata_bump "$repo" "$from" "$from_sha" "$target_sha")"
        [ "$(rank "$metadata_bump")" -le "$(rank "$bump")" ] || bump="$metadata_bump"
    fi
    version="$(resolve_version "$repo")"
    zero_x="$(is_zero_x "${version:-1.0.0}")"

    # API-diff modes currently remain unmeasured. A future computed override can
    # only RAISE the bump, never lower it.
    api_diff=unavailable
    case "$api_diff_mode" in auto|off) ;; *) echo "ERROR: invalid API-diff mode" >&2; exit 2 ;; esac
    # No structural API-diff adapter currently executes here. A tool appearing
    # on PATH is not a measured clean diff: preserve the unavailable verdict.
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
    rationale="range ${range}: highest Conventional-Commits bump=${conventional_bump}, release_metadata=${metadata_bump}, api_diff=${api_diff}, zero_x=${zero_x}"

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
