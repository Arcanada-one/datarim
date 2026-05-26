#!/usr/bin/env bash
#
# check-body-english.sh — enforce English-only body content in shipped
# Datarim instruction surface: commands/*.md, skills/<n>/SKILL.md (and
# nested fragments), agents/*.md, plugins/*/commands/*.md, plugins/*/skills/*/SKILL.md,
# and (opt-in) framework root markdown (CLAUDE.md, AGENTS.md, README.md).
#
# Orthogonal companion to check-frontmatter-english.sh (which covers the
# `description:` field). This script scans BODY content only and skips
# YAML frontmatter (delimited by the first two `^---$` lines).
#
# Allowlist:
#   - Lines inside fenced code blocks (``` or ~~~) are skipped.
#   - A line carrying `<!-- allow-non-ascii: <reason> -->` is skipped when
#     <reason> contains >= 10 non-whitespace characters; shorter reasons
#     are rejected (FAIL — marker abuse guard).
#   - Block scope: a line carrying `<!-- allow-non-ascii-block: <reason> -->`
#     (with reason >= 10 non-whitespace chars) enters skip mode for all
#     subsequent lines until a closing `<!-- /allow-non-ascii-block -->`.
#     Use sparingly for fixture content (e.g. a skill that documents
#     non-English text patterns inside a markdown table).
#
# Detection: LC_ALL=C byte regex over the UTF-8 Cyrillic block
# U+0400-U+04FF (bytes 0xD0..0xD3 followed by 0x80..0xBF).
#
# Usage:
#   check-body-english.sh [--root <repo-root>] [--scope <comma-list>] [--help]
#
# Default --root = $(pwd). Default --scope = commands,skills,agents.
# Scope tokens: commands, skills, agents, plugins, root.
#
# Exit codes:
#   0 PASS (zero Cyrillic body matches)
#   1 FAIL (one or more files have Cyrillic body content)
#   2 usage error (unknown scope token, --root outside git toplevel, etc.)
#
# Source: TUNE-0308 / TUNE-0309 Wave 1.

set -euo pipefail

ROOT="$(pwd)"
SCOPE_RAW="commands,skills,agents"

usage() {
    cat <<'USAGE'
Usage: check-body-english.sh [--root <repo-root>] [--scope <comma-list>] [--help]

Scopes (comma-separated):
  commands  -> <root>/commands/*.md
  skills    -> <root>/skills/*/SKILL.md and <root>/skills/*/*.md
  agents    -> <root>/agents/*.md
  plugins   -> <root>/plugins/*/commands/*.md, <root>/plugins/*/skills/*/SKILL.md
  root      -> <root>/CLAUDE.md, <root>/AGENTS.md, <root>/README.md

Exit codes: 0 PASS | 1 FAIL | 2 usage error.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || { echo "ERROR: --root requires an argument" >&2; exit 2; }
            ROOT="$2"; shift 2 ;;
        --scope)
            [ $# -ge 2 ] || { echo "ERROR: --scope requires an argument" >&2; exit 2; }
            SCOPE_RAW="$2"; shift 2 ;;
        --help|-h)
            usage; exit 0 ;;
        *)
            echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ ! -d "$ROOT" ]; then
    echo "ERROR: --root '$ROOT' is not a directory" >&2; exit 2
fi

# Resolve absolute path; reject roots outside any git toplevel.
ROOT_ABS="$(cd "$ROOT" && pwd -P)"
if ! git -C "$ROOT_ABS" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "ERROR: --root '$ROOT_ABS' is outside any git toplevel" >&2; exit 2
fi

# Validate scope tokens.
SCOPES=()
IFS=',' read -r -a _scope_tokens <<<"$SCOPE_RAW"
for tok in "${_scope_tokens[@]}"; do
    case "$tok" in
        commands|skills|agents|plugins|root) SCOPES+=("$tok") ;;
        "") ;;
        *) echo "ERROR: unknown scope token: '$tok'" >&2; exit 2 ;;
    esac
done
[ "${#SCOPES[@]}" -gt 0 ] || { echo "ERROR: --scope is empty" >&2; exit 2; }

# Collect files per scope (deduplicated).
collect_files() {
    local scope="$1"
    case "$scope" in
        commands)
            find "$ROOT_ABS/commands" -maxdepth 1 -type f -name '*.md' 2>/dev/null ;;
        skills)
            find "$ROOT_ABS/skills" -mindepth 2 -type f -name '*.md' 2>/dev/null ;;
        agents)
            find "$ROOT_ABS/agents" -maxdepth 1 -type f -name '*.md' 2>/dev/null ;;
        plugins)
            find "$ROOT_ABS/plugins" -type f \( -path '*/commands/*.md' -o -path '*/skills/*/SKILL.md' -o -path '*/skills/*/*.md' \) 2>/dev/null ;;
        root)
            for f in CLAUDE.md AGENTS.md README.md; do
                [ -f "$ROOT_ABS/$f" ] && printf '%s\n' "$ROOT_ABS/$f"
            done ;;
    esac
}

ALL_FILES=()
for s in "${SCOPES[@]}"; do
    while IFS= read -r f; do
        [ -n "$f" ] && ALL_FILES+=("$f")
    done < <(collect_files "$s" | sort -u)
done

# Cyrillic UTF-8 byte pattern: 0xD0..0xD3 followed by 0x80..0xBF.
# This covers U+0400..U+04FF (Cyrillic + Cyrillic Supplement).
CYRILLIC_BYTES=$'\xD0[\x80-\xBF]|\xD1[\x80-\xBF]|\xD2[\x80-\xBF]|\xD3[\x80-\xBF]'

# Scan one file; print FAIL lines to stderr; return 0 PASS, 1 FAIL.
scan_file() {
    local file="$1"
    local in_frontmatter=0
    local in_fence=0
    local fence_marker=""
    local in_block_skip=0
    local lineno=0
    local file_failed=0

    # Detect leading YAML frontmatter: starts with `---` on line 1.
    local first_line
    first_line="$(head -n 1 "$file" 2>/dev/null || true)"
    [ "$first_line" = "---" ] && in_frontmatter=1

    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))

        # Frontmatter handling.
        if [ "$in_frontmatter" -eq 1 ]; then
            if [ "$lineno" -gt 1 ] && [ "$line" = "---" ]; then
                in_frontmatter=0
            fi
            continue
        fi

        # Fenced code block handling.
        if [ "$in_fence" -eq 1 ]; then
            # Look for matching close fence.
            if [[ "$line" =~ ^[[:space:]]*"$fence_marker"[[:space:]]*$ ]]; then
                in_fence=0
                fence_marker=""
            fi
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*(\`\`\`|~~~) ]]; then
            in_fence=1
            if [[ "$line" == *'```'* ]]; then
                fence_marker='```'
            else
                fence_marker='~~~'
            fi
            continue
        fi

        # Allow-non-ascii block-scope handling.
        if [ "$in_block_skip" -eq 1 ]; then
            if [[ "$line" == *'<!-- /allow-non-ascii-block -->'* ]]; then
                in_block_skip=0
            fi
            continue
        fi
        if [[ "$line" == *'<!-- allow-non-ascii-block:'* ]]; then
            local block_reason
            block_reason="$(printf '%s' "$line" | sed -E 's/.*<!-- allow-non-ascii-block:[[:space:]]*([^>]*[^->[:space:]])[[:space:]]*-->.*/\1/')"
            local block_stripped
            block_stripped="$(printf '%s' "$block_reason" | tr -d '[:space:]')"
            if [ "${#block_stripped}" -ge 10 ]; then
                in_block_skip=1
                continue
            else
                echo "FAIL: $file:$lineno: allow-non-ascii-block reason too short (<10 non-whitespace chars): '$block_reason'" >&2
                file_failed=1
                continue
            fi
        fi

        # Allow-non-ascii marker handling (line-scope).
        if [[ "$line" == *'<!-- allow-non-ascii:'* ]]; then
            # Extract reason between `allow-non-ascii:` and the closing `-->`.
            local reason
            reason="$(printf '%s' "$line" | sed -E 's/.*<!-- allow-non-ascii:[[:space:]]*([^>]*[^->[:space:]])[[:space:]]*-->.*/\1/')"
            # Count non-whitespace chars.
            local stripped
            stripped="$(printf '%s' "$reason" | tr -d '[:space:]')"
            if [ "${#stripped}" -ge 10 ]; then
                continue
            else
                echo "FAIL: $file:$lineno: allow-non-ascii reason too short (<10 non-whitespace chars): '$reason'" >&2
                file_failed=1
                continue
            fi
        fi

        # Cyrillic byte scan under C locale.
        if printf '%s' "$line" | LC_ALL=C grep -qE "$CYRILLIC_BYTES"; then
            local preview
            preview="$(printf '%s' "$line" | cut -c 1-80)"
            echo "FAIL: $file:$lineno: $preview" >&2
            file_failed=1
        fi
    done < "$file"

    return $file_failed
}

checked=0
failures=0
for f in "${ALL_FILES[@]}"; do
    [ -f "$f" ] || continue
    checked=$((checked + 1))
    if ! scan_file "$f"; then
        failures=$((failures + 1))
    fi
done

echo "=== Summary ==="
echo "checked=$checked file(s); scope=$SCOPE_RAW; root=$ROOT_ABS"
if [ "$failures" -gt 0 ]; then
    echo "RESULT: FAIL ($failures file(s) with non-English body content)"
    exit 1
fi
echo "RESULT: PASS"
exit 0
