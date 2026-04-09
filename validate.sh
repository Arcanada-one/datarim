#!/bin/bash
# Datarim Framework Validator
# Run before every commit to ensure no forbidden content leaks into the repo.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ERRORS=0

check() {
    local label="$1"
    local pattern="$2"
    local result
    result=$(grep -ri "$pattern" "$SCRIPT_DIR" --include="*.md" --include="*.sh" | grep -v ".git/" | grep -v "validate.sh" || true)
    if [ -n "$result" ]; then
        echo "FAIL: $label"
        echo "$result"
        ERRORS=$((ERRORS + 1))
    else
        echo "PASS: $label"
    fi
}

echo "Datarim Validation Report"
echo "========================="
echo ""

# Forbidden terms
check "memory-bank references" "memory.bank\|memory_bank\|memorybank"
check "origin source references" "angry.robot\|cursor-memory\|angry-robot-deals"
check "local paths" "/Users/\|/home/"
check ".cursor references" "\.cursor"
check "/mb- command references" "/mb-"

# Cross-reference checks
echo ""
echo "Cross-Reference Checks:"
for a in planner architect developer reviewer compliance code-simplifier strategist devops writer security sre; do
    if [ -f "$SCRIPT_DIR/agents/$a.md" ]; then
        echo "  PASS: agents/$a.md exists"
    else
        echo "  FAIL: agents/$a.md MISSING"
        ERRORS=$((ERRORS + 1))
    fi
done

for s in datarim-system ai-quality compliance security testing performance tech-stack utilities consilium discovery evolution factcheck humanize; do
    if [ -f "$SCRIPT_DIR/skills/$s.md" ]; then
        echo "  PASS: skills/$s.md exists"
    else
        echo "  FAIL: skills/$s.md MISSING"
        ERRORS=$((ERRORS + 1))
    fi
done

for c in dr-init dr-prd dr-plan dr-design dr-do dr-qa dr-compliance dr-reflect dr-archive dr-status dr-continue; do
    if [ -f "$SCRIPT_DIR/commands/$c.md" ]; then
        echo "  PASS: commands/$c.md exists"
    else
        echo "  FAIL: commands/$c.md MISSING"
        ERRORS=$((ERRORS + 1))
    fi
done

for t in prd-template task-template reflection-template; do
    if [ -f "$SCRIPT_DIR/templates/$t.md" ]; then
        echo "  PASS: templates/$t.md exists"
    else
        echo "  FAIL: templates/$t.md MISSING"
        ERRORS=$((ERRORS + 1))
    fi
done

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
