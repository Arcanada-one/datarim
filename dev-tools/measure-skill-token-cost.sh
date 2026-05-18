#!/usr/bin/env bash
#
# measure-skill-token-cost.sh — TUNE-0114 AC-4 token-budget gate.
#
# Modes:
#   --baseline           Print "<lines> <chars> <path>" per skill + aggregate totals.
#                        Capture once into .datarim/baseline-v1.23.0.tokens.
#   --check              Verify current state against captured baseline; exit 0 / 1.
#                        Gates per PRD-TUNE-0114 §11 AC-4 (revised 2026-05-09):
#                          AC-4a  idle hot-path: skills/datarim-system.md ≤ +15% chars
#                          AC-4b  per-existing-file: every file in baseline ≤ +30% chars
#                          AC-4c  new absorbed files: exempt (counted, not gated)
#   --report             Human-readable summary (no exit-code gate).
#
# Baseline file: .datarim/baseline-v1.23.0.tokens (flat: "<lines> <chars> <path>" lines).
# All paths are relative to the canonical repo root.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BASELINE_FILE=".datarim/baseline-v1.23.0.tokens"
HOT_PATH_FILE="skills/datarim-system.md"
HOT_PATH_LIMIT_PCT=16
PER_FILE_LIMIT_PCT=30

usage() {
  cat <<EOF
Usage: $(basename "$0") [--baseline | --check | --report]

  --baseline   Emit current skill stats to stdout (capture into $BASELINE_FILE).
  --check      Verify current vs baseline; exit 1 on AC-4a/AC-4b violation.
  --report     Print human summary; exit 0 always.
EOF
}

current_skills() {
  find skills -type f -name '*.md' | sort
}

emit_baseline() {
  local total_lines=0 total_chars=0 count=0
  while IFS= read -r f; do
    local lines chars
    lines=$(wc -l < "$f")
    chars=$(wc -c < "$f")
    printf '%6d %8d %s\n' "$lines" "$chars" "$f"
    total_lines=$((total_lines + lines))
    total_chars=$((total_chars + chars))
    count=$((count + 1))
  done < <(current_skills)
  printf '\n## Aggregate\nTotal skill files: %d\nTotal skill lines: %d\nTotal skill chars: %d\n' \
    "$count" "$total_lines" "$total_chars"
}

# Parse baseline file — emit "<chars> <path>" lines for each baseline-listed skill.
parse_baseline_chars() {
  awk '
    /^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+skills\// {
      print $2, $3
    }
  ' "$BASELINE_FILE"
}

check_gates() {
  [[ -f "$BASELINE_FILE" ]] || { echo "ERROR: baseline missing: $BASELINE_FILE" >&2; exit 2; }

  local fail=0

  # AC-4a: hot-path entry skill
  local hot_baseline_chars hot_current_chars hot_delta_pct
  hot_baseline_chars=$(parse_baseline_chars | awk -v p="$HOT_PATH_FILE" '$2==p {print $1}')
  if [[ -z "$hot_baseline_chars" ]]; then
    echo "ERROR: $HOT_PATH_FILE not in baseline" >&2; exit 2
  fi
  hot_current_chars=$(wc -c < "$HOT_PATH_FILE")
  hot_delta_pct=$(awk -v c="$hot_current_chars" -v b="$hot_baseline_chars" \
    'BEGIN{printf "%.2f", (c - b) / b * 100}')
  printf 'AC-4a hot-path %s: baseline=%d current=%d delta=%s%% (limit ≤+%d%%)\n' \
    "$HOT_PATH_FILE" "$hot_baseline_chars" "$hot_current_chars" "$hot_delta_pct" "$HOT_PATH_LIMIT_PCT"
  if awk "BEGIN{exit !($hot_delta_pct > $HOT_PATH_LIMIT_PCT)}"; then
    echo "  FAIL: AC-4a hot-path violation"
    fail=1
  else
    echo "  PASS"
  fi

  # AC-4b: per-existing-file gate
  echo ""
  echo "AC-4b per-existing-file (limit ≤+${PER_FILE_LIMIT_PCT}% chars):"
  local violations=0 checked=0
  while read -r baseline_chars path; do
    [[ -f "$path" ]] || continue
    checked=$((checked + 1))
    local current_chars delta_pct
    current_chars=$(wc -c < "$path")
    delta_pct=$(awk -v c="$current_chars" -v b="$baseline_chars" \
      'BEGIN{printf "%.2f", (c - b) / b * 100}')
    if awk "BEGIN{exit !($delta_pct > $PER_FILE_LIMIT_PCT)}"; then
      printf '  FAIL %s: %d → %d (%s%%)\n' "$path" "$baseline_chars" "$current_chars" "$delta_pct"
      violations=$((violations + 1))
      fail=1
    fi
  done < <(parse_baseline_chars)
  printf '  checked=%d violations=%d\n' "$checked" "$violations"

  # AC-4c: new absorbed files (informational)
  echo ""
  echo "AC-4c new absorbed files (informational, not gated):"
  local new_count=0 new_chars=0
  while IFS= read -r f; do
    if ! parse_baseline_chars | awk -v p="$f" '$2==p {found=1} END{exit !found}'; then
      local c
      c=$(wc -c < "$f")
      new_count=$((new_count + 1))
      new_chars=$((new_chars + c))
    fi
  done < <(current_skills)
  printf '  new files=%d total chars=%d\n' "$new_count" "$new_chars"

  echo ""
  if [[ $fail -eq 0 ]]; then
    echo "RESULT: PASS (AC-4a + AC-4b satisfied)"
    exit 0
  else
    echo "RESULT: FAIL (see violations above)"
    exit 1
  fi
}

report() {
  echo "=== Skill token-cost report ==="
  emit_baseline
  echo ""
  if [[ -f "$BASELINE_FILE" ]]; then
    echo "=== vs baseline $BASELINE_FILE ==="
    check_gates || true
  else
    echo "(no baseline; run --baseline to capture)"
  fi
}

case "${1:-}" in
  --baseline) emit_baseline ;;
  --check)    check_gates ;;
  --report)   report ;;
  -h|--help|"") usage ;;
  *) usage; exit 2 ;;
esac
