#!/usr/bin/env bash
#
# check-skill-layout.sh — TUNE-0304 V-AC-2 gate.
#
# Validates the directory-per-skill canonical layout:
#   - skills/<name>/SKILL.md exists for every skill directory
#   - SKILL.md frontmatter `name:` equals parent directory name
#   - directory name matches kebab-case ^[a-z][a-z0-9-]{0,63}$
#   - no flat skills/<name>.md coexists alongside skills/<name>/
#
# Reserved namespace skills/.system/ is skipped (Constraint C3 — Codex bundled).
#
# Usage: check-skill-layout.sh [--root <repo-root>] [--allow-flat-coexistence]
#
# --allow-flat-coexistence tolerates skills/<name>.md alongside
#   skills/<name>/SKILL.md (the Phase 2-4 hybrid window). Phase 5 contract
#   removal is verified by running this script WITHOUT the flag — at that
#   point all flat originals must be gone.
#
# Exit 0 on PASS, 1 on FAIL.

set -euo pipefail

ROOT=""
ALLOW_FLAT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --allow-flat-coexistence) ALLOW_FLAT=1; shift ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$ROOT" ]]; then
    ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

SKILLS_DIR="$ROOT/skills"
if [[ ! -d "$SKILLS_DIR" ]]; then
    echo "ERROR: skills/ not found under $ROOT" >&2
    exit 2
fi

fail=0
checked=0

kebab_re='^[a-z][a-z0-9-]{0,63}$'

extract_name_field() {
    awk '
        BEGIN { in_fm = 0; line_count = 0 }
        /^---$/ {
            if (line_count == 0) { in_fm = 1; line_count++; next }
            if (in_fm == 1) { exit }
        }
        in_fm == 1 && /^name:[[:space:]]*/ {
            sub(/^name:[[:space:]]*/, "")
            sub(/[[:space:]]*#.*$/, "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            print
            exit
        }
    ' "$1"
}

for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] || continue
    base="$(basename "$skill_dir")"
    # Skip reserved Codex bundled namespace.
    [[ "$base" == ".system" ]] && continue

    checked=$((checked + 1))

    if ! [[ "$base" =~ $kebab_re ]]; then
        echo "FAIL ($base): directory name violates kebab-case ^[a-z][a-z0-9-]{0,63}\$"
        fail=1
        continue
    fi

    skill_md="$skill_dir/SKILL.md"
    if [[ ! -f "$skill_md" ]]; then
        echo "FAIL ($base): missing SKILL.md at $skill_md"
        fail=1
        continue
    fi

    fm_name="$(extract_name_field "$skill_md" || true)"
    if [[ -z "$fm_name" ]]; then
        echo "FAIL ($base): SKILL.md has no frontmatter name: field"
        fail=1
        continue
    fi
    if [[ "$fm_name" != "$base" ]]; then
        echo "FAIL ($base): name mismatch — frontmatter says '$fm_name', dir is '$base'"
        fail=1
        continue
    fi

    flat_md="$SKILLS_DIR/$base.md"
    if [[ -f "$flat_md" ]]; then
        if [[ "$ALLOW_FLAT" -eq 1 ]]; then
            echo "OK-HYBRID ($base): flat .md coexists with directory ($flat_md) — tolerated under --allow-flat-coexistence"
        else
            echo "FAIL ($base): flat .md coexists with directory ($flat_md)"
            fail=1
            continue
        fi
    fi
done

echo ""
echo "=== Summary ==="
echo "checked=$checked skill directories under $SKILLS_DIR"

if [[ $fail -eq 0 ]]; then
    echo "RESULT: PASS (V-AC-2 layout)"
    exit 0
else
    echo "RESULT: FAIL"
    exit 1
fi
