#!/usr/bin/env bash
#
# check-jargon-gloss.sh — enforce that framework-internal jargon terms carry
# an inline gloss on their first occurrence in any shipped instruction file
# (commands/skills/agents/root). Companion to check-body-english.sh; same
# scope conventions + same fence-skip + same frontmatter-skip rules.
#
# Manifest: dev-tools/data/jargon-bank.txt (one term per line; '#' comments;
# blank lines ignored). Each manifest term, when first used in a file's
# body, MUST be followed within 80 characters by one of:
#   - a parenthetical `(`     — e.g. `FB-1..8 (the eight feedback rules…)`
#   - a markdown link `](`    — e.g. `FB-1..8 ([autonomous-agents](…))`
# Subsequent occurrences in the same file are NOT re-checked.
#
# Usage:
#   check-jargon-gloss.sh [--root <repo-root>] [--scope <comma-list>]
#                        [--manifest <path>] [--help]
#
# Default --root = $(pwd). Default --scope = commands,skills,agents,root.
# Default --manifest = <root>/dev-tools/data/jargon-bank.txt.
#
# Exit codes:
#   0 PASS (every first-use has a same-line gloss)
#   1 FAIL (one or more terms first-used without inline gloss)
#   2 usage error
#
# Security: all paths quoted; `--` option terminator before filename args.
# Source: PRD-TUNE-0308 V-AC-5.

set -euo pipefail

ROOT="$(pwd)"
SCOPE_RAW="commands,skills,agents,root"
MANIFEST=""

usage() {
    cat <<'USAGE'
Usage: check-jargon-gloss.sh [--root <repo-root>] [--scope <comma-list>] [--manifest <path>] [--help]

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
        --manifest)
            [ $# -ge 2 ] || { echo "ERROR: --manifest requires an argument" >&2; exit 2; }
            MANIFEST="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ ! -d "$ROOT" ]; then
    echo "ERROR: --root '$ROOT' is not a directory" >&2; exit 2
fi
ROOT_ABS="$(cd -- "$ROOT" && pwd -P)"
if ! git -C "$ROOT_ABS" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "ERROR: --root '$ROOT_ABS' is outside any git toplevel" >&2; exit 2
fi

[ -z "$MANIFEST" ] && MANIFEST="$ROOT_ABS/dev-tools/data/jargon-bank.txt"
if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: manifest not found: '$MANIFEST'" >&2; exit 2
fi

# Parse manifest: skip blank + comment lines.
TERMS=()
while IFS= read -r raw || [ -n "$raw" ]; do
    line="${raw%%#*}"                                    # strip trailing comment
    line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [ -n "$line" ] && TERMS+=("$line")
done < "$MANIFEST"
[ "${#TERMS[@]}" -gt 0 ] || { echo "ERROR: manifest is empty: '$MANIFEST'" >&2; exit 2; }

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
                # Resolve symlink once to avoid double-scanning AGENTS.md → CLAUDE.md.
                if [ -L "$ROOT_ABS/$f" ]; then continue; fi
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

# Emit body lines (skipping frontmatter + fenced code) as "lineno<TAB>content".
emit_body() {
    local file="$1"
    awk '
        BEGIN { in_fm=0; in_fence=0; fence=""; first=1 }
        {
            if (first==1) {
                first=0
                if ($0=="---") { in_fm=1; next }
            }
            if (in_fm==1) {
                if (NR>1 && $0=="---") { in_fm=0 }
                next
            }
            if (in_fence==1) {
                line=$0
                # strip leading whitespace for fence-close match
                sub(/^[[:space:]]+/, "", line)
                if (line==fence) { in_fence=0; fence="" }
                next
            }
            line=$0
            sub(/^[[:space:]]+/, "", line)
            if (line ~ /^```/ || line ~ /^~~~/) {
                in_fence=1
                if (line ~ /^```/) fence="```"; else fence="~~~"
                next
            }
            print NR "\t" $0
        }
    ' "$file"
}

failures=0
checked=0
for file in "${ALL_FILES[@]}"; do
    [ -f "$file" ] || continue
    checked=$((checked + 1))
    body="$(emit_body "$file")"
    for term in "${TERMS[@]}"; do
        # Find first body line containing the term (literal, case-sensitive).
        match="$(printf '%s\n' "$body" | grep -F -m 1 -- "$term" || true)"
        [ -z "$match" ] && continue
        lineno="${match%%	*}"
        content="${match#*	}"
        # Locate term inside content, examine the 80 chars following it.
        # Use awk for portability with potentially special chars.
        tail="$(printf '%s' "$content" | awk -v t="$term" '
            { i=index($0, t); if (i==0) { print ""; exit } print substr($0, i+length(t), 80) }
        ')"
        if printf '%s' "$tail" | grep -qE '\(|\]\('; then
            continue
        fi
        echo "FAIL: $file:$lineno: term '$term' first-used without inline gloss" >&2
        failures=$((failures + 1))
    done
done

echo "=== Summary ==="
echo "checked=$checked file(s); scope=$SCOPE_RAW; manifest=$MANIFEST; root=$ROOT_ABS"
if [ "$failures" -gt 0 ]; then
    echo "RESULT: FAIL ($failures missing-gloss finding(s))"
    exit 1
fi
echo "RESULT: PASS"
exit 0
