#!/usr/bin/env bash
#
# DEPRECATED — use dev-tools/measure-invocation-token-cost.sh instead.
#
# This script's data source path (~/.local/share/coworker/log.jsonl) and the
# parser shape (`data.get('calls', [])`) do not match the current coworker
# JSONL log format (~/.local/state/coworker/log/<YYYY-MM-DD>.jsonl with
# OpenTelemetry-style dotted keys, aggregated-by-provider in `coworker stats`).
# Side-by-side keep for transitional reference; remove via follow-up backlog
# entry after 30 days.
#
# Original: cost overhead measurement; computed token_overhead_pct.
# Replacement provides per-task aggregation with provider breakdown.
#
# Inputs:
#   --task <TASK-ID>      Task ID для cost measurement
#   --baseline-tokens N   Baseline /dr-do token cost (operator captures separately)
#   --output <path>       Output report path (default: appended to datarim/qa/empirical-{TASK-ID}.md)
#
# Exit 0 always (gate decision logged, not enforced).

set -euo pipefail

echo "[DEPRECATED] measure-verify-cost.sh — use dev-tools/measure-invocation-token-cost.sh instead. This script reads a stale path/schema and may emit zero on real logs." >&2

TASK_ID=""
BASELINE_TOKENS=0
OUTPUT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task) TASK_ID="$2"; shift 2 ;;
    --baseline-tokens) BASELINE_TOKENS="$2"; shift 2 ;;
    --output) OUTPUT_PATH="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$TASK_ID" ]]; then
  echo "ERROR: --task <TASK-ID> required" >&2
  exit 2
fi

if [[ -z "$OUTPUT_PATH" ]]; then
  OUTPUT_PATH="datarim/qa/empirical-${TASK_ID}.md"
fi

# Default coworker stats invocation
VERIFY_TOKENS=$(~/.local/bin/coworker stats --since 1d --format json 2>/dev/null \
  | python3 -c "
import json, sys
try:
  data = json.load(sys.stdin)
  total = sum(c.get('prompt_tokens', 0) + c.get('completion_tokens', 0) for c in data.get('calls', []))
  print(total)
except Exception:
  print(0)
" 2>/dev/null || echo 0)

if [[ "$BASELINE_TOKENS" -gt 0 ]]; then
  OVERHEAD_PCT=$(awk "BEGIN {printf \"%.1f\", (($VERIFY_TOKENS - $BASELINE_TOKENS) / $BASELINE_TOKENS) * 100}")
else
  OVERHEAD_PCT="N/A"
fi

if [[ "$OVERHEAD_PCT" != "N/A" ]] && (( $(echo "$OVERHEAD_PCT <= 25" | bc -l) )); then
  GATE="PASS"
elif [[ "$OVERHEAD_PCT" != "N/A" ]]; then
  GATE="WARN_EXCEED_25PCT"
else
  GATE="UNMEASURED"
fi

cat >> "$OUTPUT_PATH" <<EOF

## Cost Overhead Measurement (AC-8) — Task $TASK_ID

- baseline_tokens: $BASELINE_TOKENS
- verify_tokens: $VERIFY_TOKENS
- overhead_pct: ${OVERHEAD_PCT}%
- gate: $GATE

EOF

echo "Cost overhead: ${OVERHEAD_PCT}% — gate: $GATE"
exit 0
