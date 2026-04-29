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
#                                  [--diff-only [<base>]]
#
# Inputs:
#   <file-or-dir>   Path to scan. File → single-file mode. Directory →
#                   recursive *.md scan (excluding tests/fixtures/).
#   --whitelist     Optional, repeatable. Default whitelist: skills/tech-stack.md.
#                   Whitelist match is suffix-based (path ends with the value).
#   --diff-only     Scan only lines added in `git diff <base> -- <file>` —
#                   ignore pre-existing baseline matches (TUNE-0058). Default
#                   base = HEAD. Optional positional next arg is treated as
#                   base if it does not exist as a filesystem path. Single-file
#                   target outside a git repo or untracked → exit 2; directory
#                   scan silently skips untracked files. Source incident:
#                   TUNE-0044 + TUNE-0056 self-dogfood operator-toll on
#                   docs/evolution-log.md (pre-existing matches kept failing
#                   the gate every archive even when the current task did not
#                   touch them).
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

set -uo pipefail

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
    "skills/ai-quality/deployment-patterns.md"
    "skills/testing/live-smoke-gates.md"
    "skills/utilities/ga4-admin.md"
)

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
TARGET=""
DIFF_ONLY=0
DIFF_BASE="HEAD"
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
        --diff-only)
            DIFF_ONLY=1
            shift
            # Optional next positional: treat as base ref if it doesn't start
            # with a flag and doesn't resolve to an existing filesystem path
            # (refs and SHAs aren't paths under normal cwd). User can still
            # disambiguate by passing `./main` to force path interpretation.
            if [ $# -gt 0 ] && [ "${1#-}" = "$1" ] && [ ! -e "$1" ]; then
                DIFF_BASE="$1"
                shift
            fi
            ;;
        --help|-h)
            sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
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
# blocks. Reads from stdin, writes to stdout; line numbers preserved by
# replacing skipped lines with blanks (so grep -n still maps to the original
# stream offset). In --diff-only mode the stream is the added-lines only, so
# numbers refer to "added-line N" rather than file line N.
strip_example_blocks() {
    awk '
        /<!-- gate:example-only -->/ { skip=1; print ""; next }
        /<!-- \/gate:example-only -->/ { skip=0; print ""; next }
        { if (skip) print ""; else print }
    '
}

# Produce the content stream that scan_file should examine for `$1`. In full
# mode this is just the file. In --diff-only mode it is the added lines from
# `git diff <base> -- <file>` (without the leading `+` and without `+++`
# headers). On diff-only failures returns non-zero — caller decides whether
# that is a hard error (single-file mode) or a silent skip (directory mode).
produce_scan_stream() {
    local file="$1"
    if [ "$DIFF_ONLY" -ne 1 ]; then
        cat "$file"
        return 0
    fi
    local repo_root
    repo_root="$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null)" || return 2
    if ! git -C "$repo_root" ls-files --error-unmatch -- "$file" >/dev/null 2>&1; then
        return 2
    fi
    git -C "$repo_root" diff "$DIFF_BASE" -- "$file" 2>/dev/null \
        | awk '/^\+\+\+ /{next} /^\+/{print substr($0,2)}'
}

SCAN_FILE_HITS=0

# Compose all denylist patterns into one ERE alternation. Single grep call
# per file avoids fd-leak under bash 3.2 nested process-substitution.
DENYLIST_REGEX=""
for kw in "${DENYLIST[@]}"; do
    if [ -z "$DENYLIST_REGEX" ]; then
        DENYLIST_REGEX="$kw"
    else
        DENYLIST_REGEX="$DENYLIST_REGEX|$kw"
    fi
done

SCAN_FILE_DIFF_SKIP=0

scan_file() {
    SCAN_FILE_HITS=0
    SCAN_FILE_DIFF_SKIP=0
    local file="$1"
    if is_whitelisted "$file"; then
        return 0
    fi

    # produce_scan_stream emits the content to scan (full file in default
    # mode, added-lines-only in --diff-only). Non-zero = non-git or untracked
    # file in --diff-only — flag for caller.
    local stream
    if ! stream="$(produce_scan_stream "$file")"; then
        SCAN_FILE_DIFF_SKIP=1
        return 0
    fi

    # Strip <!-- gate:example-only --> blocks then run a single ERE-alternation
    # grep against the combined denylist. -w (whole-word) prevents the classic
    # false-positive trap (e.g. "RSpec" matching inside "perspective"). -i for
    # case-insensitive. -n for line numbers. -o gives matching token only,
    # which we use to label each hit precisely.
    local matches
    matches="$(printf '%s\n' "$stream" | strip_example_blocks | grep -n -w -i -E -o -- "$DENYLIST_REGEX" 2>/dev/null || true)"

    [ -z "$matches" ] && return 0

    while IFS= read -r match; do
        [ -n "$match" ] || continue
        local line_no="${match%%:*}"
        local kw="${match#*:}"
        printf '%s:%s:%s\n' "$file" "$line_no" "$kw" >&2
        SCAN_FILE_HITS=$((SCAN_FILE_HITS + 1))
    done <<< "$matches"

    return 0
}

# ---------------------------------------------------------------------------
# Main scan
# ---------------------------------------------------------------------------
TOTAL_HITS=0
FILES_WITH_HITS=0

scan_path() {
    local path="$1"
    if [ -f "$path" ]; then
        scan_file "$path"
        if [ "$DIFF_ONLY" -eq 1 ] && [ "$SCAN_FILE_DIFF_SKIP" -eq 1 ]; then
            echo "stack-agnostic-gate: --diff-only requires a tracked file inside a git repo: $path" >&2
            exit 2
        fi
        if [ "$SCAN_FILE_HITS" -gt 0 ]; then
            TOTAL_HITS=$((TOTAL_HITS + SCAN_FILE_HITS))
            FILES_WITH_HITS=$((FILES_WITH_HITS + 1))
        fi
    elif [ -d "$path" ]; then
        # Recursive *.md scan. Exclude tests/fixtures/ — fixtures are
        # intentionally stack-specific to validate the gate itself.
        while IFS= read -r f; do
            scan_file "$f"
            if [ "$SCAN_FILE_HITS" -gt 0 ]; then
                TOTAL_HITS=$((TOTAL_HITS + SCAN_FILE_HITS))
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
