#!/usr/bin/env bash
# stack-agnostic-gate.sh — pre-apply linter rejecting stack-specific content
# in Datarim runtime files (skills/agents/commands/templates).
#
# Source contract: skills/evolution/stack-agnostic-gate.md.
# Source incident: VERD-0010 + VERD-0021 — three Class A proposals containing
# NestJS / npm / fetch-migration wording passed reflection approval and leaked
# into framework runtime; reverted manually. This gate enforces the rule the
# user-memory `feedback_datarim_stack_agnostic.md` already declares.
#
# Usage:
#   scripts/stack-agnostic-gate.sh <file-or-dir> [--whitelist <path>] ...
#
# Inputs:
#   <file-or-dir>   Path to scan. File → single-file mode. Directory →
#                   recursive *.md scan (excluding tests/fixtures/).
#   --whitelist     Optional, repeatable. Default whitelist: skills/tech-stack.md.
#                   Whitelist match is suffix-based (path ends with the value).
#
# Output (stderr):
#   Per match: "<path>:<line>:<keyword>: <context>"
#   Summary:   "FAIL: N matches in M files" or "PASS: clean"
#
# Exit codes:
#   0  clean (no matches)
#   1  matches found
#   2  invocation error (path missing, etc.)
#
# Implementation notes:
#   - Pure bash + grep, bash 3.2 compatible (macOS default).
#   - Denylist is the array literal below — single source of truth for the
#     keywords this gate considers stack-specific. Extend conservatively.
#   - Escape hatch for legitimate examples: wrap a fenced block in
#     `<!-- gate:example-only -->` markers (handled by skipping any line
#     between an opening and closing marker). Use sparingly.
#   - Read-only: no writes, no network, no exec of scanned content.

set -euo pipefail

# ---------------------------------------------------------------------------
# Denylist (case-insensitive). Extend as new ecosystems leak.
# ---------------------------------------------------------------------------
DENYLIST=(
    # Frameworks
    "NestJS"
    "Fastify"
    "Express\.js"
    "Next\.js"
    "Django"
    "FastAPI"
    "Spring Boot"
    "Vitest"
    "Jest"
    "Pytest"
    "Mocha"
    "RSpec"
    # Package-manager invocations (the verb form — the noun "npm" alone
    # would false-positive on prose like "npm-style ecosystem")
    "npm install"
    "npm audit"
    "pnpm install"
    "pnpm add"
    "pnpm audit"
    "yarn add"
    "yarn install"
    "pip install"
    "pip-audit"
    "cargo add"
    "cargo audit"
    "composer install"
    "bundle install"
    "bundle audit"
    "gem install"
    "go mod"
    # Stack-specific runtimes / libs
    "Prisma"
    "BullMQ"
    "axios"
    "bcryptjs"
    "Zod"
)

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
WHITELIST=(
    "skills/tech-stack.md"
    "skills/evolution/stack-agnostic-gate.md"
)

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
TARGET=""
while [ $# -gt 0 ]; do
    case "$1" in
        --whitelist)
            shift
            [ $# -gt 0 ] || { echo "stack-agnostic-gate: --whitelist requires a value" >&2; exit 2; }
            WHITELIST+=("$1")
            shift
            ;;
        --reset-whitelist)
            WHITELIST=()
            shift
            ;;
        --help|-h)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --*)
            echo "stack-agnostic-gate: unknown flag $1" >&2
            exit 2
            ;;
        *)
            if [ -z "$TARGET" ]; then
                TARGET="$1"
            else
                echo "stack-agnostic-gate: only one target path supported (got '$TARGET' and '$1')" >&2
                exit 2
            fi
            shift
            ;;
    esac
done

if [ -z "$TARGET" ]; then
    echo "Usage: stack-agnostic-gate.sh <file-or-dir> [--whitelist <path>]" >&2
    exit 2
fi

if [ ! -e "$TARGET" ]; then
    echo "stack-agnostic-gate: path not found: $TARGET" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
is_whitelisted() {
    local path="$1"
    local entry
    for entry in "${WHITELIST[@]:-}"; do
        [ -n "$entry" ] || continue
        case "$path" in
            *"$entry") return 0 ;;
        esac
    done
    return 1
}

# Strip lines inside <!-- gate:example-only --> ... <!-- /gate:example-only -->
# blocks. Output goes to stdout; line numbers preserved by replacing skipped
# lines with blanks (so grep -n still maps to the original file line).
strip_example_blocks() {
    awk '
        /<!-- gate:example-only -->/ { skip=1; print ""; next }
        /<!-- \/gate:example-only -->/ { skip=0; print ""; next }
        { if (skip) print ""; else print }
    ' "$1"
}

scan_file() {
    local file="$1"
    if is_whitelisted "$file"; then
        return 0
    fi

    local stripped
    stripped="$(strip_example_blocks "$file")"

    local hits=0
    local kw
    for kw in "${DENYLIST[@]}"; do
        # grep -n -i with fixed-string-ish pattern. Patterns above use \. for
        # literal dots, so we use ERE (-E).
        while IFS= read -r match; do
            [ -n "$match" ] || continue
            local line_no="${match%%:*}"
            local context="${match#*:}"
            printf '%s:%s:%s: %s\n' "$file" "$line_no" "$kw" "$context" >&2
            hits=$((hits + 1))
        done < <(printf '%s\n' "$stripped" | grep -n -w -i -E -- "$kw" || true)
    done

    return "$hits"
}

# ---------------------------------------------------------------------------
# Main scan
# ---------------------------------------------------------------------------
TOTAL_HITS=0
FILES_WITH_HITS=0

scan_path() {
    local path="$1"
    if [ -f "$path" ]; then
        local file_hits=0
        scan_file "$path" || file_hits=$?
        if [ "$file_hits" -gt 0 ]; then
            TOTAL_HITS=$((TOTAL_HITS + file_hits))
            FILES_WITH_HITS=$((FILES_WITH_HITS + 1))
        fi
    elif [ -d "$path" ]; then
        # Recursive *.md scan. Exclude tests/fixtures/ — fixtures are
        # intentionally stack-specific to validate the gate itself.
        while IFS= read -r f; do
            local file_hits=0
            scan_file "$f" || file_hits=$?
            if [ "$file_hits" -gt 0 ]; then
                TOTAL_HITS=$((TOTAL_HITS + file_hits))
                FILES_WITH_HITS=$((FILES_WITH_HITS + 1))
            fi
        done < <(find "$path" -type f -name '*.md' \
                    -not -path '*/tests/fixtures/*' \
                    -not -path '*/node_modules/*' \
                    -not -path '*/.git/*' \
                    | sort)
    fi
}

scan_path "$TARGET"

if [ "$TOTAL_HITS" -eq 0 ]; then
    echo "PASS: clean" >&2
    exit 0
fi

echo "FAIL: $TOTAL_HITS matches in $FILES_WITH_HITS files" >&2
exit 1
