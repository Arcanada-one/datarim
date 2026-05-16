#!/usr/bin/env bash
#
# check-v-ac-mandate-preflight.sh — /dr-prd V-AC pre-save advisory gate.
#
# Scans the V-AC / Verification / Success Criteria block of a PRD draft and
# emits a WARNING on stdout when any candidate line matches a forbidden
# pattern from the Public Surface Hygiene Mandate contract surface
# (default: sibling public-surface-forbidden.regex).
#
# Advisory only — always exits 0 on a completed scan. Exit 2 reserved for
# usage errors (missing --prd, missing or empty regex file).
#
# Usage:
#   check-v-ac-mandate-preflight.sh --prd FILE [--regex FILE] [--report]
#   check-v-ac-mandate-preflight.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_REGEX="${SCRIPT_DIR}/public-surface-forbidden.regex"

prd_file=""
regex_file="${DEFAULT_REGEX}"
report=0

usage() {
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

err_usage() {
    usage >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prd)
            shift
            [ $# -gt 0 ] || { echo "ERROR: --prd requires a path argument" >&2; err_usage; }
            prd_file="$1"
            shift
            ;;
        --regex)
            shift
            [ $# -gt 0 ] || { echo "ERROR: --regex requires a path argument" >&2; err_usage; }
            regex_file="$1"
            shift
            ;;
        --report)
            report=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            err_usage
            ;;
    esac
done

if [ -z "$prd_file" ]; then
    echo "ERROR: --prd FILE is required" >&2
    err_usage
fi

if [ ! -f "$prd_file" ]; then
    echo "ERROR: PRD file not found: $prd_file" >&2
    exit 2
fi

if [ ! -f "$regex_file" ]; then
    echo "ERROR: regex file not found: $regex_file" >&2
    exit 2
fi

patterns=()
while IFS= read -r raw; do
    case "$raw" in
        ''|\#*) continue ;;
        *) patterns+=("$raw") ;;
    esac
done < "$regex_file"

if [ ${#patterns[@]} -eq 0 ]; then
    echo "ERROR: regex file has no active patterns: $regex_file" >&2
    exit 2
fi

# Extract candidate V-AC lines.
#   Pattern A: line matching ^\s*[-*]\s*(V-)?AC-[0-9]+
#   Pattern B: line containing literal **Verification:**
#   Pattern C: any line inside a "## Success Criteria" block (until next "## ")
candidates=$(awk '
    BEGIN { in_sc = 0 }
    /^## Success Criteria[[:space:]]*$/ { in_sc = 1; next }
    /^## / { in_sc = 0 }
    {
        if (in_sc || $0 ~ /^[[:space:]]*[-*][[:space:]]*(V-)?AC-[0-9]+/ || $0 ~ /\*\*Verification:\*\*/) {
            printf("%d\t%s\n", NR, $0)
        }
    }
' "$prd_file")

if [ -z "$candidates" ]; then
    [ "$report" -eq 1 ] && echo "PASS: no V-AC candidate lines in PRD"
    exit 0
fi

prd_basename="$(basename "$prd_file")"
findings=0
candidate_count=0

while IFS=$'\t' read -r line_no line_text; do
    [ -z "$line_no" ] && continue
    candidate_count=$((candidate_count + 1))
    for pattern in "${patterns[@]}"; do
        if printf '%s' "$line_text" | grep -E -q -- "$pattern"; then
            excerpt="${line_text:0:120}"
            printf 'WARNING: %s:%s: V-AC text matches mandate pattern «%s»: %s\n' \
                "$prd_basename" "$line_no" "$pattern" "$excerpt"
            findings=$((findings + 1))
        fi
    done
done <<< "$candidates"

if [ "$report" -eq 1 ]; then
    printf 'scan complete: %d finding(s) across %d candidate line(s)\n' \
        "$findings" "$candidate_count"
fi

exit 0
