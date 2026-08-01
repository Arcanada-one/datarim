#!/bin/bash
# Datarim Framework Validator
# Checks that all framework components exist and are referenced in CLAUDE.md.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ERRORS=0

echo "Datarim Validation Report"
echo "========================="
echo ""

# Cross-reference checks — verify all directories have files
echo ""
echo "Cross-Reference Checks:"

for dir in agents skills commands templates; do
    count=$(find "$SCRIPT_DIR/$dir" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$dir" = "skills" ]; then
        # Directory-per-skill layout: also count subdir-shaped skills/<name>/SKILL.md.
        sub_count=$(find "$SCRIPT_DIR/$dir" -maxdepth 2 -name "SKILL.md" -type f 2>/dev/null | wc -l | tr -d ' ')
        count=$((count + sub_count))
    fi
    if [ "$count" -gt 0 ]; then
        echo "  PASS: $dir/ contains $count files"
    else
        echo "  FAIL: $dir/ is empty or missing"
        ERRORS=$((ERRORS + 1))
    fi

    # Verify each file in the directory is referenced in CLAUDE.md
    for f in "$SCRIPT_DIR/$dir"/*.md; do
        [ -f "$f" ] || continue
        basename=$(basename "$f" .md)
        # Skip checking if basename appears in CLAUDE.md (case-insensitive)
        if ! grep -qi "$basename" "$SCRIPT_DIR/CLAUDE.md" 2>/dev/null; then
            echo "  WARN: $dir/$basename.md not referenced in CLAUDE.md"
        fi
    done
done

# Documentation tree check.
# `docs/` was renamed to `documentation/` at v2.49.0. This check still probed
# the old path, so it leaked a `find: .../docs: No such file or directory`
# to stderr, reported 0, and — because nothing incremented ERRORS — still
# announced ALL CHECKS PASSED. A missing documentation tree is now a real
# failure.
echo ""
# Severity is graduated on purpose:
#   present but empty -> FAIL. The tree exists and is broken; that is a real
#                        defect in a full checkout.
#   absent            -> WARN. A skeletal or partial checkout (and the bats
#                        fixture repo) legitimately ships the install scopes
#                        without a documentation tree, so absence alone is
#                        not evidence of breakage in this repo.
echo "Documentation Check:"
if [ -d "$SCRIPT_DIR/documentation" ]; then
    doc_count=$(find "$SCRIPT_DIR/documentation" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$doc_count" -gt 0 ]; then
        echo "  PASS: documentation/ contains $doc_count documents"
    else
        echo "  FAIL: documentation/ exists but contains no .md files"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "  WARN: documentation/ directory not present (partial checkout?)"
fi

# Double-prefix check
echo ""
result=$(grep -r "dr-dr-" "$SCRIPT_DIR" --include="*.md" | grep -v ".git/" || true)
if [ -n "$result" ]; then
    echo "FAIL: double-prefix (dr-dr-) found"
    echo "$result"
    ERRORS=$((ERRORS + 1))
else
    echo "PASS: no double-prefix (dr-dr-)"
fi

# v1.17.0: detect local/ overlay overrides
LOCAL_DIR="${CLAUDE_DIR:-$HOME/.claude}/local"
if [ -d "$LOCAL_DIR" ]; then
    echo ""
    echo "Local Overlay Override Check:"
    OVERRIDE_COUNT=0
    CRITICAL_OVERRIDE_COUNT=0
    for scope in skills agents commands templates; do
        [ -d "$LOCAL_DIR/$scope" ] || continue
        # Collect both flat-layout (scope/*.md) and directory-per-skill (skills/*/SKILL.md) overrides.
        candidates=()
        for f in "$LOCAL_DIR/$scope"/*.md; do
            [ -f "$f" ] && candidates+=("$f|$(basename "$f")")
        done
        if [ "$scope" = "skills" ]; then
            for f in "$LOCAL_DIR/$scope"/*/SKILL.md; do
                [ -f "$f" ] || continue
                dname=$(basename "$(dirname "$f")")
                candidates+=("$f|$dname/SKILL.md")
            done
        fi
        for entry in "${candidates[@]}"; do
            f="${entry%%|*}"
            bname="${entry##*|}"
            if [ -f "$SCRIPT_DIR/$scope/$bname" ]; then
                # Critical-skill blocklist: shadowing security-contract surfaces is rejected (exit 1).
                # Source list locked: skills/datarim-system/SKILL.md § Loading Order; documentation/tutorials/getting-started.md § Personal additions.
                case "$scope/$bname" in
                    skills/security/SKILL.md|skills/security-baseline/SKILL.md|skills/compliance/SKILL.md|skills/datarim-system/SKILL.md|skills/ai-quality/SKILL.md|skills/evolution/SKILL.md)
                        echo "  ERROR: critical skill '$scope/$bname' cannot be overridden via local/ overlay (security contract). Remove $LOCAL_DIR/$scope/$bname or rename it."
                        CRITICAL_OVERRIDE_COUNT=$((CRITICAL_OVERRIDE_COUNT + 1))
                        ERRORS=$((ERRORS + 1))
                        ;;
                    *)
                        echo "  WARN: override detected: local/$scope/$bname shadows $scope/$bname"
                        ;;
                esac
                OVERRIDE_COUNT=$((OVERRIDE_COUNT + 1))
            fi
        done
    done
    if [ "$OVERRIDE_COUNT" -eq 0 ]; then
        echo "  INFO: no local overrides detected"
    else
        echo "  INFO: $OVERRIDE_COUNT override(s) — review local/README.md"
        if [ "$CRITICAL_OVERRIDE_COUNT" -gt 0 ]; then
            echo "  INFO: $CRITICAL_OVERRIDE_COUNT critical override(s) — exit 1 (blocked)"
        fi
    fi
fi

# Summary counts
echo ""
# Counting rules — one shipped component per unit, NOT every .md on disk:
#   agents/commands/templates  one file at depth 1 (`-maxdepth 1`). A bare
#                              recursive find over templates/ also swept the
#                              documentation-diataxis/*/README.md stubs and
#                              reported 29 instead of 25.
#   skills                     one directory per skill, `skills/<name>/SKILL.md`.
#                              A recursive find counted supporting fragment
#                              files too and reported 129 instead of 67.
#   documentation              recursive: the tree is organised into Diataxis
#                              subdirectories, so depth 1 holds no .md at all.
echo "Framework Inventory:"
echo "  Agents:    $(find "$SCRIPT_DIR/agents" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')"
echo "  Skills:    $(find "$SCRIPT_DIR/skills" -mindepth 2 -maxdepth 2 -name "SKILL.md" -type f 2>/dev/null | wc -l | tr -d ' ')"
echo "  Commands:  $(find "$SCRIPT_DIR/commands" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')"
echo "  Templates: $(find "$SCRIPT_DIR/templates" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')"
echo "  Docs:      $(find "$SCRIPT_DIR/documentation" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')"

# Summary
echo ""
echo "========================="
if [ "$ERRORS" -eq 0 ]; then
    echo "ALL CHECKS PASSED"
    exit 0
else
    echo "FAILED: $ERRORS error(s) found"
    exit 1
fi
