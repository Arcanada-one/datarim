#!/usr/bin/env bash
# check-component-counts.sh — framework component counts-drift enforcer (TUNE-0174).
#
# Repo-self-consistency check, distinct from check-repo-site-sync.sh's
# repo-vs-site drift detection (which needs an external cross-repo registry).
# This script has NO cross-repo dependency: it enforces that the component
# counts claimed in THIS repo's own CLAUDE.md / README.md ("NN agents",
# "NN skills", "NN commands", "NN templates" — parenthesized declaration
# form, e.g. "(19 agents)") match the actual on-disk counts:
#
#   commands   find commands  -mindepth 1 -maxdepth 1 -name '*.md' | wc -l
#   agents     find agents    -mindepth 1 -maxdepth 1 -name '*.md' | wc -l
#   skills     find skills    -mindepth 1 -maxdepth 1 -type d      | wc -l   (one dir per skill, SKILL.md inside)
#   templates  find templates -mindepth 1 -maxdepth 1 -name '*.md' | wc -l
#
# KNOWN GAP (out of scope for this script, tracked as a follow-up): this
# check does NOT extend to the public site (datarim.club — pages/about.php,
# content/en.php, content/ru.php). That is a repo-vs-site check and belongs
# in check-repo-site-sync.sh's registry-driven mechanism (would need a new
# registry.yml entry/field in the separate arcanada workspace, which this
# repo's dev-tools cannot and must not touch). See TUNE-0174 PR body.
#
# Dependency floor: pure bash + find + grep + wc. No yq, no python.
#
# Usage:
#   check-component-counts.sh [--check | --report] [--root <dir>]
#
# Exit codes:
#   0  clean (all claims match actual counts, or no claims found)
#   1  at least one category has a claim/actual mismatch
#   2  usage error
#   3  root not found (no CLAUDE.md / README.md at resolved root)
#
# Read-only: no writes, no network.

set -uo pipefail

SCRIPT_NAME="check-component-counts.sh"
MODE="check"            # check | report
ROOT=""

print_usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--check | --report] [--root <dir>]

  --check        exit 0 = all counts match, 1 = drift found (default)
  --report       human-readable per-category findings
  --root <dir>   repo root (default: walk up from cwd to find CLAUDE.md)
  --help         this message

Exit: 0 clean | 1 drift | 2 usage error | 3 root not found
EOF
}

# ---- arg parse ----
while [ $# -gt 0 ]; do
    case "$1" in
        --check)  MODE="check"; shift ;;
        --report) MODE="report"; shift ;;
        --root)   ROOT="${2:-}"; shift 2 ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; print_usage >&2; exit 2 ;;
    esac
done

# ---- resolve repo root ----
if [ -z "$ROOT" ]; then
    d="$PWD"
    while [ "$d" != "/" ]; do
        if [ -f "$d/CLAUDE.md" ]; then ROOT="$d"; break; fi
        d="$(dirname "$d")"
    done
fi
if [ -z "$ROOT" ] || [ ! -f "$ROOT/CLAUDE.md" ]; then
    echo "ERROR: repo root not found (no CLAUDE.md)" >&2
    exit 3
fi

CATEGORIES="commands agents skills templates"

# Actual on-disk count for a category. Echoes an integer (0 if dir absent).
actual_count() {  # $1=category
    local cat="$1" dir="$ROOT/$1"
    [ -d "$dir" ] || { echo 0; return; }
    case "$cat" in
        skills) find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' ;;
        *)      find "$dir" -mindepth 1 -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ' ;;
    esac
}

# Claimed count for a category in a given doc file. Parenthesized
# declaration form only, e.g. "(19 agents)" / "(64 skills, ...)" — this is
# the format both CLAUDE.md and README.md use at their canonical count
# declaration points, and it avoids false positives from illustrative
# prose elsewhere (e.g. "Documentation says 15 agents but disk has 12",
# ">20 skills" threshold examples — neither is parenthesized).
# Echoes the first match's number, or nothing if no claim found.
claimed_count() {  # $1=file $2=category
    local file="$1" cat="$2"
    [ -f "$file" ] || return
    grep -oE "\([0-9]+ ${cat}\b" "$file" 2>/dev/null | head -1 | grep -oE '[0-9]+'
}

FINDINGS=""   # accumulates "<file>|<category>|<claimed>|<actual>"
add_finding() { FINDINGS="${FINDINGS}${1}|${2}|${3}|${4}"$'\n'; }

for doc in "$ROOT/CLAUDE.md" "$ROOT/README.md"; do
    [ -f "$doc" ] || continue
    doc_name="$(basename "$doc")"
    for cat in $CATEGORIES; do
        claim="$(claimed_count "$doc" "$cat")"
        [ -n "$claim" ] || continue
        actual="$(actual_count "$cat")"
        if [ "$claim" != "$actual" ]; then
            add_finding "$doc_name" "$cat" "$claim" "$actual"
        fi
    done
done

DRIFT="$(printf '%s' "$FINDINGS" | awk -F'|' 'NF>=4 {c++} END{print c+0}')"

if [ "$MODE" = "report" ]; then
    if [ -z "$FINDINGS" ]; then
        echo "OK: all component-count claims match on-disk counts."
    else
        printf '%s' "$FINDINGS" | awk -F'|' 'NF>=4 {printf "%-12s %-10s claims %-4s actual %-4s\n", $1, $2, $3, $4}'
    fi
fi

[ "$DRIFT" -gt 0 ] && exit 1
exit 0
