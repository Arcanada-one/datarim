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

# Docs directory check
echo ""
doc_count=$(find "$SCRIPT_DIR/docs" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
echo "  INFO: docs/ contains $doc_count reference documents"

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

# v1.17.0 (TUNE-0033 AC-7): detect local/ overlay overrides
LOCAL_DIR="${CLAUDE_DIR:-$HOME/.claude}/local"
if [ -d "$LOCAL_DIR" ]; then
    echo ""
    echo "Local Overlay Override Check:"
    OVERRIDE_COUNT=0
    for scope in skills agents commands templates; do
        [ -d "$LOCAL_DIR/$scope" ] || continue
        for f in "$LOCAL_DIR/$scope"/*.md; do
            [ -f "$f" ] || continue
            bname=$(basename "$f")
            if [ -f "$SCRIPT_DIR/$scope/$bname" ]; then
                echo "  WARN: override detected: local/$scope/$bname shadows $scope/$bname"
                OVERRIDE_COUNT=$((OVERRIDE_COUNT + 1))
            fi
        done
    done
    if [ "$OVERRIDE_COUNT" -eq 0 ]; then
        echo "  INFO: no local overrides detected"
    else
        echo "  INFO: $OVERRIDE_COUNT override(s) — review local/README.md"
    fi
fi

# Summary counts
echo ""
echo "Framework Inventory:"
echo "  Agents:    $(find "$SCRIPT_DIR/agents" -name "*.md" | wc -l | tr -d ' ')"
echo "  Skills:    $(find "$SCRIPT_DIR/skills" -name "*.md" | wc -l | tr -d ' ')"
echo "  Commands:  $(find "$SCRIPT_DIR/commands" -name "*.md" | wc -l | tr -d ' ')"
echo "  Templates: $(find "$SCRIPT_DIR/templates" -name "*.md" | wc -l | tr -d ' ')"
echo "  Docs:      $(find "$SCRIPT_DIR/docs" -name "*.md" | wc -l | tr -d ' ')"

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
