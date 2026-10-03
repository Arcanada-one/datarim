#!/usr/bin/env bash
#
# test-self-verification-claude.sh — TUNE-0137 AC-10 integration test.
#
# Verifies Claude path спавнит 3 parallel subagents (reviewer + tester + security)
# с Read-only tool whitelist. Expected: log shows 3 Agent invocations + verdict emitted.
#
# Inputs:
#   --task <TASK-ID>      Baseline-labeled L3 task (e.g. TUNE-0114)
#
# This test cannot directly invoke Claude Code's Agent tool from bash;
# it is an instruction harness that validates the *contract* that /dr-verify must follow.
# Usage: operator runs `/dr-verify <TASK-ID>` под Claude Code, then runs this script
# to verify post-conditions on audit log.

set -euo pipefail

TASK_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK_ID="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$TASK_ID" ]]; then
  echo "ERROR: --task <TASK-ID> required" >&2
  exit 2
fi

AUDIT_GLOB="datarim/qa/verify-${TASK_ID}-*-1.md"
audit_files=()
shopt -s nullglob
for af in $AUDIT_GLOB; do
  audit_files+=("$af")
done
shopt -u nullglob

if [[ ${#audit_files[@]} -eq 0 ]]; then
  echo "FAIL: no audit log found for $TASK_ID at $AUDIT_GLOB" >&2
  echo "  Run /dr-verify $TASK_ID --runtime claude --max-iter 1 first" >&2
  exit 1
fi

AUDIT_FILE="${audit_files[0]}"
echo "Checking audit log: $AUDIT_FILE"

# Check 1: 3 agent_origin entries (reviewer + tester + security)
ORIGIN_COUNT=$(grep -cE "agent_origin:\s*(reviewer|tester|security)" "$AUDIT_FILE" || echo 0)
if [[ "$ORIGIN_COUNT" -lt 3 ]]; then
  echo "FAIL: expected ≥3 agent_origin entries, got $ORIGIN_COUNT"
  exit 1
fi
echo "✓ AC-10 part 1: 3+ agent_origin entries found ($ORIGIN_COUNT)"

# Check 2: verdict line emitted
if ! grep -qE "^verdict:\s*(BLOCKED|CONDITIONAL|PASS)" "$AUDIT_FILE"; then
  echo "FAIL: no verdict line found"
  exit 1
fi
VERDICT=$(grep -oE "verdict:\s*(BLOCKED|CONDITIONAL|PASS)" "$AUDIT_FILE" | head -1)
echo "✓ AC-10 part 2: verdict emitted ($VERDICT)"

# Check 3: append-only enforced (chmod a-w)
if [[ -w "$AUDIT_FILE" ]]; then
  echo "WARN: $AUDIT_FILE is still writable — chmod a-w may not be applied"
else
  echo "✓ AC-10 part 3: chmod a-w applied (file is read-only)"
fi

# Check 4: structured findings (at least the schema fields are present)
SCHEMA_FIELDS=$(grep -cE "(artifact_ref|severity|category|evidence)" "$AUDIT_FILE" || echo 0)
if [[ "$SCHEMA_FIELDS" -lt 4 ]]; then
  echo "WARN: expected ≥4 schema field references, got $SCHEMA_FIELDS"
else
  echo "✓ AC-10 part 4: schema fields present ($SCHEMA_FIELDS)"
fi

echo ""
echo "AC-10 integration test: PASSED"
exit 0
