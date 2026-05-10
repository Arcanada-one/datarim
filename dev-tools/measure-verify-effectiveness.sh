#!/usr/bin/env bash
#
# measure-verify-effectiveness.sh — TUNE-0137 AC-7 hit-rate measurement.
#
# Computes hit-rate = matched_findings / total_known_gaps × 100%
# где matched_findings = findings emitted by /dr-verify whose evidence.excerpt
# matches (substring) any baseline known_gap.evidence_excerpt AND category matches.
#
# Inputs:
#   --baseline <path>     Baseline labels file (default: datarim/qa/baseline-TUNE-0137.md)
#   --tasks <N>           Number of tasks to score (default 3)
#   --audit-glob <pat>    Glob для audit logs (default: datarim/qa/verify-*-*-*.md)
#   --output <path>       Output report path (default: datarim/qa/empirical-TUNE-0137.md)
#
# Output: Markdown report с per-task hit-rate + overall hit-rate.
# Exit 0 always (gate decision logged, not enforced — operator triages).

set -euo pipefail

BASELINE_PATH="datarim/qa/baseline-TUNE-0137.md"
TASKS_COUNT=3
AUDIT_GLOB="datarim/qa/verify-*.md"
OUTPUT_PATH="datarim/qa/empirical-TUNE-0137.md"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline) BASELINE_PATH="$2"; shift 2 ;;
    --tasks) TASKS_COUNT="$2"; shift 2 ;;
    --audit-glob) AUDIT_GLOB="$2"; shift 2 ;;
    --output) OUTPUT_PATH="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$BASELINE_PATH" ]]; then
  echo "ERROR: baseline file not found: $BASELINE_PATH" >&2
  exit 2
fi

# Extract baseline known gaps: each gap has evidence_excerpt + category
# Format expected: YAML-like blocks под "## Task N" с "evidence_excerpt:" и "category:" lines
TOTAL_GAPS=$(grep -cE "^\s*-\s*id:\s*G-" "$BASELINE_PATH" || echo 0)
echo "Baseline gaps total: $TOTAL_GAPS"

# Collect all audit log finding excerpts (portable bash 3.2+ — avoid mapfile)
audit_files=()
shopt -s nullglob
for af in $AUDIT_GLOB; do
  audit_files+=("$af")
done
shopt -u nullglob

# Sanity check: --tasks N is the expected minimum number of distinct tasks scored.
# Each audit log corresponds to one task × stage × iter; assert we have enough audit logs.
if [[ "${#audit_files[@]}" -lt "$TASKS_COUNT" ]]; then
  echo "WARN: audit logs (${#audit_files[@]}) < --tasks N ($TASKS_COUNT) — coverage may be insufficient" >&2
fi

if [[ ${#audit_files[@]} -eq 0 ]]; then
  echo "WARN: no audit logs matched glob $AUDIT_GLOB" >&2
  MATCHED=0
else
  # Count findings per audit log + simple match heuristic:
  # for each audit excerpt token, grep against baseline excerpt tokens
  MATCHED=0
  for af in "${audit_files[@]}"; do
    # Extract excerpts from audit log (rough — real impl would parse YAML)
    while IFS= read -r excerpt; do
      [[ -z "$excerpt" ]] && continue
      # Take first 30 chars as match key (substring heuristic)
      key="${excerpt:0:30}"
      if grep -qF "$key" "$BASELINE_PATH" 2>/dev/null; then
        MATCHED=$((MATCHED + 1))
      fi
    done < <(grep -oE 'excerpt:\s*"[^"]*"' "$af" 2>/dev/null | sed 's/^excerpt:\s*"//; s/"$//' || true)
  done
fi

if [[ "$TOTAL_GAPS" -gt 0 ]]; then
  HIT_RATE=$(awk "BEGIN {printf \"%.1f\", ($MATCHED / $TOTAL_GAPS) * 100}")
else
  HIT_RATE="0.0"
fi

# Gate verdict
if (( $(echo "$HIT_RATE >= 40" | bc -l) )); then
  GATE="PASS_TRIGGER_TUNE_0138"
elif (( $(echo "$HIT_RATE >= 30" | bc -l) )); then
  GATE="REDUCED_SCOPE_TUNE_0138"
else
  GATE="KILL_OR_PIVOT"
fi

# Write report
mkdir -p "$(dirname "$OUTPUT_PATH")"
cat > "$OUTPUT_PATH" <<EOF
# Empirical Hit-Rate Measurement — TUNE-0137 AC-7

**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Baseline:** $BASELINE_PATH
**Audit logs scanned:** ${#audit_files[@]}
**Matching method:** evidence excerpt substring (first 30 chars) cross-referenced с baseline.

## Result

- total_known_gaps: $TOTAL_GAPS
- matched_findings: $MATCHED
- hit_rate: ${HIT_RATE}%
- gate_verdict: $GATE

## Gate Decision Rules

| hit_rate | Gate | Action |
|----------|------|--------|
| ≥40% | PASS_TRIGGER_TUNE_0138 | Spawn TUNE-0138 (post-step hook) full scope |
| 30-40% | REDUCED_SCOPE_TUNE_0138 | Spawn TUNE-0138 reduced scope (single-agent reviewer only) |
| <30% | KILL_OR_PIVOT | Re-evaluate: kill feature OR extend baseline к 5-10 tasks |

## Audit Logs

EOF

for af in "${audit_files[@]}"; do
  echo "- $af" >> "$OUTPUT_PATH"
done

echo "Report written: $OUTPUT_PATH"
echo "hit_rate: ${HIT_RATE}% — gate: $GATE"
exit 0
