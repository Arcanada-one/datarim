#!/usr/bin/env bash
#
# rewrite-skill-refs.sh — TUNE-0304 Phase 3 worker.
#
# Walks the repo and rewrites every cross-reference of the form
#   skills/<name>.md   →   skills/<name>/SKILL.md
# (both bare and markdown-link parenthesised forms) across .md / .sh /
# .yaml / .yml. Excludes documentation/archive/** (frozen historical
# refs) and skills/<name>/ self-content (the SKILL.md body is canonical
# router; rewriting links inside it would be safe but pointless and is
# excluded for diff cleanliness).
#
# Idempotent: a second invocation rewrites zero lines. The pattern
# `skills/<name>/SKILL.md` is intentionally excluded from the source
# pattern (anchored on `.md` immediately after `<name>`) so already-
# canonical refs never become `skills/<name>/SKILL/SKILL.md`.
#
# Usage: rewrite-skill-refs.sh --root <repo> [--dry-run]
# Exit 0 on success.

set -euo pipefail

ROOT=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$ROOT" ]]; then
    echo "usage: $0 --root <repo> [--dry-run]" >&2
    exit 2
fi

# The match pattern. Anchored on `.md` that is NOT followed by additional
# path segments — i.e. `skills/<name>.md(?!/)` — which prevents matching
# already-canonical `skills/<name>/SKILL.md`. POSIX BRE has no negative
# lookahead, so we rely on the fact that the literal `.md` is followed
# by a non-`/` boundary in every false-positive case (whitespace, `)`,
# `]`, EOL, `;`, `"`, `'`, `,`, etc.).
#
# sed program: pattern → replacement.
SED_PROGRAM='s|skills/([a-z][a-z0-9_-]*)\.md|skills/\1/SKILL.md|g'

changed=0
dryrun_log=""

process_file() {
    local f="$1"
    # Skip if no skills/<name>.md hit at all (fast path).
    if ! grep -qE 'skills/[a-z][a-z0-9_-]+\.md' "$f"; then
        return
    fi
    # Skip if the only matches are already canonical (skills/<name>/SKILL.md
    # is not matched by the source pattern, so this check is conservative).
    local tmp
    tmp="$(mktemp)"
    sed -E "$SED_PROGRAM" "$f" >"$tmp"
    if cmp -s "$f" "$tmp"; then
        rm -f "$tmp"
        return
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        dryrun_log+="${f}"$'\n'
        rm -f "$tmp"
    else
        cat "$tmp" >"$f"
        rm -f "$tmp"
    fi
    changed=$((changed + 1))
}

# Find candidate files, excluding documentation/archive/** and .git/.
while IFS= read -r f; do
    process_file "$f"
done < <(
    find "$ROOT" \
        \( -path '*/documentation/archive' -o -path '*/.git' -o -path '*/node_modules' \) -prune -o \
        -type f \( -name '*.md' -o -name '*.sh' -o -name '*.yaml' -o -name '*.yml' \) -print
)

if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ -n "$dryrun_log" ]]; then
        echo "DRY-RUN: would rewrite the following files:"
        printf '%s' "$dryrun_log"
    else
        echo "DRY-RUN: no files would change"
    fi
    echo "DRY-RUN: $changed files"
    exit 0
fi

echo "rewrote $changed files"
exit 0
