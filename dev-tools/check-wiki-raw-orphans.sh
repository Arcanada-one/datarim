#!/usr/bin/env bash
#
# check-wiki-raw-orphans.sh — semantic orphan-content check for `wiki/_raw_/`.
#
# Ships as a standalone dev-tools validator per the Validation Discipline
# (CLAUDE.md § Self-Evolution): content validation is orthogonal to ops-file
# migration and MUST NOT live inside datarim-doctor.sh.
#
# WHAT IT DETECTS
#   Raw-dump files whose basename bears no relation to their own first
#   content heading (or first non-empty line when no heading exists). Such
#   "orphans" typically come from bulk imports where the filename was
#   auto-generated or copy-pasted from an unrelated source — they defeat
#   filename-based lookup and rot silently.
#
# HEURISTIC (deterministic, pure bash + grep/awk/tr)
#   1. basename tokens: file name without extension, lowercased, split on
#      any non-alphanumeric run; tokens shorter than 3 chars and purely
#      numeric tokens are dropped (dates, counters, initials carry no
#      semantic signal).
#   2. heading tokens: the first markdown heading line (`#`..`######`), or
#      the first non-empty line if the file has no heading, tokenised the
#      same way.
#   3. A file is an ORPHAN when the two token sets share ZERO tokens
#      (substring match counts: token "sync" matches heading token
#      "syncthing"). Files that yield no usable basename tokens or no
#      usable heading tokens are SKIPPED (reported in --report), never
#      flagged — an empty token set proves nothing.
#
# SCOPE
#   *.md files directly under, or nested below, the target directory.
#   Default target: ./wiki/_raw_ (override with --dir). When the target
#   directory does not exist the check is a NO-OP: exit 0 with a note —
#   most consumer projects have no wiki/_raw_ corpus.
#
# USAGE
#   check-wiki-raw-orphans.sh [--dir <path>] --check    # exit 0 clean / 1 orphans
#   check-wiki-raw-orphans.sh [--dir <path>] --report   # human-readable detail, always exit 0
#
# Exit codes: 0 PASS (or no-op / report mode), 1 orphans found (--check), 2 usage.

set -euo pipefail

DIR="wiki/_raw_"
MODE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) DIR="${2:-}"; shift 2 ;;
        --check) MODE="check"; shift ;;
        --report) MODE="report"; shift ;;
        -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo "usage: check-wiki-raw-orphans.sh [--dir <path>] (--check|--report)" >&2
    exit 2
fi

if [[ ! -d "$DIR" ]]; then
    echo "NOTE: target dir '$DIR' does not exist — nothing to check (no-op)."
    exit 0
fi

# tokenise <string> → newline-separated lowercase tokens, len>=3, not numeric.
tokenise() {
    printf '%s\n' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -cs '[:alnum:]' '\n' \
        | awk 'length($0) >= 3 && $0 !~ /^[0-9]+$/'
}

# first_content_line <file> → first markdown heading, else first non-empty line.
first_content_line() {
    local heading
    heading="$(grep -m1 -E '^#{1,6}[[:space:]]' "$1" 2>/dev/null || true)"
    if [[ -n "$heading" ]]; then
        printf '%s\n' "$heading"
    else
        awk 'NF { print; exit }' "$1"
    fi
}

orphans=0
scanned=0
skipped=0

while IFS= read -r file; do
    scanned=$((scanned + 1))

    base="$(basename "$file")"
    base="${base%.*}"
    base_tokens="$(tokenise "$base")"

    content_line="$(first_content_line "$file")"
    head_tokens="$(tokenise "$content_line")"

    if [[ -z "$base_tokens" || -z "$head_tokens" ]]; then
        skipped=$((skipped + 1))
        if [[ "$MODE" == "report" ]]; then
            echo "SKIP  $file (no usable tokens; first line: '${content_line:-<empty>}')"
        fi
        continue
    fi

    match=0
    while IFS= read -r bt; do
        while IFS= read -r ht; do
            if [[ "$ht" == *"$bt"* || "$bt" == *"$ht"* ]]; then
                match=1
                break 2
            fi
        done <<< "$head_tokens"
    done <<< "$base_tokens"

    if [[ "$match" -eq 0 ]]; then
        orphans=$((orphans + 1))
        echo "ORPHAN  $file"
        echo "        basename tokens: $(echo "$base_tokens" | tr '\n' ' ')"
        echo "        first content:   $content_line"
    elif [[ "$MODE" == "report" ]]; then
        echo "OK    $file"
    fi
done < <(find "$DIR" -type f -name '*.md' | LC_ALL=C sort)

echo ""
echo "=== Summary ==="
echo "scanned=$scanned orphans=$orphans skipped=$skipped (dir: $DIR)"

if [[ "$MODE" == "check" && "$orphans" -gt 0 ]]; then
    echo "RESULT: FAIL — $orphans file(s) whose name bears no relation to their content"
    exit 1
fi
echo "RESULT: PASS"
exit 0
