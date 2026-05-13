#!/usr/bin/env bash
#
# public-surface-lint.sh — Public Surface Hygiene Mandate gate.
#
# Walks the supplied --paths (default: README.md CHANGELOG.md CONTRIBUTING.md
# docs/ packages) and greps for forbidden references loaded from a sibling
# `.regex` file (default: dev-tools/public-surface-forbidden.regex).
#
# Single mode: exit 0 on PASS (no findings), exit 1 on FAIL (>=1 finding),
# exit 2 on usage error. No mutation.
#
# Usage:
#   public-surface-lint.sh [--regex FILE] [--paths PATH...] [--report]
#   public-surface-lint.sh --help
#
# Consumers extend the regex set by passing --regex <consumer>.regex pointing
# at their own merged file (this script does not concatenate sets — keep one
# source of truth per invocation).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_REGEX="${SCRIPT_DIR}/public-surface-forbidden.regex"
DEFAULT_PATHS=(README.md CHANGELOG.md CONTRIBUTING.md docs packages)

regex_file="${DEFAULT_REGEX}"
paths=()
report=0

usage() {
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --regex)
            shift
            [ $# -gt 0 ] || usage
            regex_file="$1"
            shift
            ;;
        --paths)
            shift
            while [ $# -gt 0 ] && [[ "$1" != --* ]]; do
                paths+=("$1")
                shift
            done
            ;;
        --report)
            report=1
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage
            ;;
    esac
done

if [ ! -f "$regex_file" ]; then
    echo "ERROR: regex file not found: $regex_file" >&2
    exit 2
fi

if [ ${#paths[@]} -eq 0 ]; then
    paths=("${DEFAULT_PATHS[@]}")
fi

# Filter to existing paths only (skip silently — consumers may not have all
# default categories present).
existing_paths=()
for p in "${paths[@]}"; do
    if [ -e "$p" ]; then
        existing_paths+=("$p")
    fi
done

if [ ${#existing_paths[@]} -eq 0 ]; then
    [ "$report" -eq 1 ] && echo "no paths to scan (all defaults absent)"
    exit 0
fi

# Load patterns (drop comments + blank lines).
patterns=()
while IFS= read -r line; do
    case "$line" in
        ''|\#*) continue ;;
        *) patterns+=("$line") ;;
    esac
done < "$regex_file"

if [ ${#patterns[@]} -eq 0 ]; then
    echo "ERROR: regex file has no active patterns: $regex_file" >&2
    exit 2
fi

findings=0
finding_log=""

for pattern in "${patterns[@]}"; do
    # grep -r -E -n on existing paths, exclude dist/ build/ node_modules/ .venv/
    # to skip generated artefacts (tarballs are scanned via the published
    # tarball, not the working tree).
    matches=$(grep -r -E -n --binary-files=without-match \
        --exclude-dir=dist --exclude-dir=build --exclude-dir=node_modules \
        --exclude-dir=.venv --exclude-dir=__pycache__ --exclude-dir=.git \
        --exclude-dir=.pytest_cache \
        -e "$pattern" "${existing_paths[@]}" 2>/dev/null || true)
    if [ -n "$matches" ]; then
        count=$(printf '%s\n' "$matches" | wc -l | tr -d ' ')
        findings=$((findings + count))
        if [ "$report" -eq 1 ]; then
            finding_log+="--- pattern: ${pattern}"$'\n'
            finding_log+="${matches}"$'\n'
        fi
    fi
done

if [ "$findings" -gt 0 ]; then
    if [ "$report" -eq 1 ]; then
        printf '%s' "$finding_log"
    fi
    echo "FAIL: ${findings} forbidden reference(s) found in public surface" >&2
    exit 1
fi

[ "$report" -eq 1 ] && echo "PASS: clean (scanned ${#existing_paths[@]} path(s), ${#patterns[@]} pattern(s))"
exit 0
