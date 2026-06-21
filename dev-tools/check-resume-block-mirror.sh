#!/usr/bin/env bash
# check-resume-block-mirror.sh — byte-identity gate for the resume-block fence.
#
# The resume-block template fence appears in two canonical locations:
#   commands/dr-save.md        § Step 5 — Emit the resume block
#   skills/session-handoff-writer/SKILL.md  § Resume block
#
# Both fences MUST be byte-identical. This script
# extracts the fenced code block from each file, diffs them, and exits 1 on
# any mismatch.
#
# Usage:
#   check-resume-block-mirror.sh [--check | --report] [--root <dir>]
#
# Exit codes:
#   0  fences are byte-identical
#   1  drift detected (fences differ)
#   2  usage error or missing file
#
# Dependency floor: pure bash + awk + diff (POSIX). No yq, no python.
# Read-only: no writes, no network. All path references are resolved from
# the script's own directory or the --root arg and are quoted throughout
# (Security Mandate S1).

set -uo pipefail

SCRIPT_NAME="check-resume-block-mirror.sh"
MODE="check"   # check | report
ROOT=""

_usage() {
    cat >&2 <<EOF
Usage: $SCRIPT_NAME [--check | --report] [--root <dir>]

  --check        exit 0 = identical, 1 = drift (default)
  --report       print a unified diff when drift exists
  --root <dir>   framework root (default: two levels up from this script)
  --help         this message

Exit codes: 0 identical | 1 drift | 2 usage/file error
EOF
}

# Parse args.
while [ $# -gt 0 ]; do
    case "$1" in
        --check)        MODE="check";  shift ;;
        --report)       MODE="report"; shift ;;
        --root)         ROOT="$2";     shift 2 ;;
        --help|-h)      _usage; exit 0 ;;
        *) printf '%s: unknown argument: %s\n' "$SCRIPT_NAME" "$1" >&2
           _usage; exit 2 ;;
    esac
done

# Resolve root: explicit arg, else two levels up from this script's dir.
if [ -z "$ROOT" ]; then
    _self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ROOT="$(cd "${_self_dir}/.." && pwd)"
fi

FILE_A="${ROOT}/commands/dr-save.md"
FILE_B="${ROOT}/skills/session-handoff-writer/SKILL.md"

for _f in "$FILE_A" "$FILE_B"; do
    if [ ! -f "$_f" ]; then
        printf '%s: file not found: %s\n' "$SCRIPT_NAME" "$_f" >&2
        exit 2
    fi
done

# Extract the resume-block fenced code block from a file.
# Strategy: find the first ```...``` block that follows a "resume block"
# heading (case-insensitive). If not found, fall back to the FIRST
# fenced block that contains "/dr-continue" — which is the resume fence.
#
# Uses awk: reads between the opening ``` and closing ``` fence markers,
# skips the fence line itself, emits only the block body.
_extract_fence() {
    local file="$1"
    awk '
        BEGIN { in_block=0; found=0; past_heading=0 }
        # Track when we pass a "resume block" / "emit the resume" heading.
        /[Rr]esume block|[Ee]mit the resume/ { past_heading=1; next }
        # Opening fence after heading.
        past_heading && /^```$/ && !in_block {
            in_block=1
            next
        }
        # Closing fence.
        in_block && /^```$/ {
            in_block=0
            found=1
            # Stop after first matching block.
            exit
        }
        in_block { print }
    ' "$file"
}

TMP_A=""
TMP_B=""

_cleanup() {
    rm -f "$TMP_A" "$TMP_B"
}
trap _cleanup EXIT

TMP_A="$(mktemp "${TMPDIR:-/tmp}/resume-mirror-a.XXXXXX")"
TMP_B="$(mktemp "${TMPDIR:-/tmp}/resume-mirror-b.XXXXXX")"

_extract_fence "$FILE_A" > "$TMP_A"
_extract_fence "$FILE_B" > "$TMP_B"

# Guard: if either extract is empty, the fence was not found — that is itself a
# drift condition (one file may be missing the block entirely).
if [ ! -s "$TMP_A" ]; then
    printf '%s: resume-block fence not found in: %s\n' "$SCRIPT_NAME" "$FILE_A" >&2
    exit 1
fi
if [ ! -s "$TMP_B" ]; then
    printf '%s: resume-block fence not found in: %s\n' "$SCRIPT_NAME" "$FILE_B" >&2
    exit 1
fi

if diff -q "$TMP_A" "$TMP_B" > /dev/null 2>&1; then
    # Identical.
    if [ "$MODE" = "report" ]; then
        printf '%s: OK — resume-block fences are byte-identical.\n' "$SCRIPT_NAME"
    fi
    exit 0
else
    # Drift detected.
    if [ "$MODE" = "report" ]; then
        printf '%s: DRIFT — resume-block fences differ:\n\n' "$SCRIPT_NAME" >&2
        diff -u \
            --label "commands/dr-save.md (Step 5 fence)" \
            --label "skills/session-handoff-writer/SKILL.md (Resume block fence)" \
            "$TMP_A" "$TMP_B" >&2 || true
    else
        printf '%s: resume-block fences differ between dr-save.md and session-handoff-writer/SKILL.md\n' \
            "$SCRIPT_NAME" >&2
        printf '%s: run with --report for a unified diff.\n' "$SCRIPT_NAME" >&2
    fi
    exit 1
fi
