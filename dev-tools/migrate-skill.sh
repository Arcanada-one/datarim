#!/usr/bin/env bash
#
# migrate-skill.sh — TUNE-0304 Phase 2/3 worker.
#
# Migrates a single skill from flat `skills/<name>.md` to the canonical
# `skills/<name>/SKILL.md` layout, normalising frontmatter:
#   - drops top-level `runtime:` (legacy; migration window)
#   - rewrites `model: sonnet|opus|haiku` → `model: inherit`
#   - preserves all other frontmatter keys verbatim and in original order
#   - body content copied verbatim
#
# The flat file is COPIED (not moved); Phase 5 contract step removes the
# flat originals once cross-refs are rewritten and live runtime is verified.
#
# Usage:
#   migrate-skill.sh --root <repo> --skill <name> [--dry-run] [--force]
#
# Exit codes:
#   0  migrated successfully OR idempotent (target exists with expected
#      normalised content)
#   1  target SKILL.md exists with different content (without --force)
#   3  invalid skill name or missing prerequisites

set -euo pipefail

ROOT=""
SKILL=""
DRY_RUN=0
FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --skill) SKILL="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$ROOT" || -z "$SKILL" ]]; then
    echo "usage: $0 --root <repo> --skill <name> [--dry-run] [--force]" >&2
    exit 2
fi

# Validate skill name as kebab-case ≤ 64 chars.
kebab_re='^[a-z][a-z0-9-]{0,63}$'
if ! [[ "$SKILL" =~ $kebab_re ]]; then
    echo "FAIL: skill name '$SKILL' violates kebab-case ^[a-z][a-z0-9-]{0,63}\$" >&2
    exit 3
fi

FLAT="$ROOT/skills/$SKILL.md"
DIR="$ROOT/skills/$SKILL"
TARGET="$DIR/SKILL.md"

if [[ ! -f "$FLAT" ]]; then
    echo "FAIL: $FLAT not found" >&2
    exit 3
fi

# Normalise frontmatter into a tempfile. We process only the first
# frontmatter block (between the first two `---` lines); body is copied
# verbatim afterwards.
normalised_tmp="$(mktemp)"
trap 'rm -f "$normalised_tmp"' EXIT

awk '
    BEGIN { fm_state = 0 }   # 0=before, 1=inside, 2=after
    /^---$/ {
        if (fm_state == 0) { fm_state = 1; print; next }
        if (fm_state == 1) { fm_state = 2; print; next }
    }
    fm_state == 1 {
        # Drop top-level `runtime:` line entirely (migration: contract drop).
        if ($0 ~ /^runtime:[[:space:]]/) { next }
        # Rewrite `model: sonnet|opus|haiku` → `model: inherit`.
        if ($0 ~ /^model:[[:space:]]+(sonnet|opus|haiku)[[:space:]]*(#.*)?$/) {
            # Preserve any trailing comment.
            comment = ""
            if (match($0, /#.*$/)) {
                comment = " " substr($0, RSTART, RLENGTH)
            }
            print "model: inherit" comment
            next
        }
        print
        next
    }
    { print }
' "$FLAT" >"$normalised_tmp"

# Idempotency / safety check before writing.
if [[ -f "$TARGET" ]]; then
    if cmp -s "$normalised_tmp" "$TARGET"; then
        echo "OK: $TARGET already matches normalised form (idempotent)"
        exit 0
    fi
    if [[ "$FORCE" -ne 1 ]]; then
        echo "FAIL: $TARGET exists with different content; pass --force to overwrite" >&2
        exit 1
    fi
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY-RUN: would create $DIR/ and write SKILL.md"
    echo "DRY-RUN: planned normalised frontmatter:"
    awk '/^---$/{f++; print; if (f==2) exit; next} f==1 {print}' "$normalised_tmp"
    exit 0
fi

mkdir -p "$DIR"
# Atomic install: rename within the same filesystem (writer wrote a tempfile
# under /tmp, which may be a different fs on macOS, so we copy not rename).
cp "$normalised_tmp" "$TARGET"

echo "OK: migrated $SKILL → $TARGET (flat source preserved at $FLAT)"
exit 0
