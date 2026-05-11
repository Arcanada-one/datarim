#!/usr/bin/env bash
# measure-orchestrator-soak.sh — V-AC-22 soak verdict gate for /dr-orchestrate
# Phase 2. Computes false-escalation rate from schema_version=2 audit events:
#   false_escalate_rate = escalated / (resolved + escalated)
# Exit 0 if rate < threshold (default 0.15), exit 1 if >= threshold or no data,
# exit 2 on usage error.
set -euo pipefail

AUDIT_DIR="${DR_ORCH_AUDIT_DIR:-$HOME/.local/share/datarim-orchestrate}"
SINCE="48h"
THRESHOLD="0.15"
VERBOSE=0

usage() {
  cat <<'USAGE'
usage: measure-orchestrator-soak.sh [--audit-dir DIR] [--since 48h|24h|7d|...]
                                    [--max-false-escalate RATE] [-v|--verbose]

Computes false-escalation rate from schema_version=2 audit events.
Exit 0  rate < threshold
Exit 1  rate >= threshold OR no events in window
Exit 2  usage error
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    --audit-dir)          AUDIT_DIR="$2"; shift 2 ;;
    --since)              SINCE="$2"; shift 2 ;;
    --max-false-escalate) THRESHOLD="$2"; shift 2 ;;
    -v|--verbose)         VERBOSE=1; shift ;;
    -h|--help)            usage; exit 0 ;;
    *)                    echo "ERR: unknown arg '$1'" >&2; usage >&2; exit 2 ;;
  esac
done

case "$SINCE" in
  *h)  secs=$(( ${SINCE%h} * 3600 )) ;;
  *m)  secs=$(( ${SINCE%m} * 60 )) ;;
  *d)  secs=$(( ${SINCE%d} * 86400 )) ;;
  *)   echo "ERR: --since must end in h/m/d (got '$SINCE')" >&2; exit 2 ;;
esac

cutoff_ts=$(( $(date -u +%s) - secs ))
resolved=0; escalated=0

shopt -s nullglob
files=( "$AUDIT_DIR"/audit-*.jsonl )
if (( ${#files[@]} == 0 )); then
  echo "soak: no audit files in $AUDIT_DIR" >&2
  exit 1
fi

while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  schema=$(jq -r '.schema_version // 0' <<<"$line" 2>/dev/null || echo 0)
  [[ "$schema" -eq 2 ]] || continue
  ts_iso=$(jq -r '.timestamp // .ts // ""' <<<"$line" 2>/dev/null || echo "")
  [[ -n "$ts_iso" ]] || continue
  # GNU and BSD date both accept ISO-8601 via -d (GNU) or -j -f (BSD)
  ts_epoch=$(date -u -j -f %Y-%m-%dT%H:%M:%SZ "$ts_iso" +%s 2>/dev/null \
             || date -u -d "$ts_iso" +%s 2>/dev/null || echo 0)
  (( ts_epoch >= cutoff_ts )) || continue
  outcome=$(jq -r '.outcome // ""' <<<"$line")
  case "$outcome" in
    resolved)  resolved=$((resolved+1)) ;;
    escalated) escalated=$((escalated+1)) ;;
  esac
done < <(cat "${files[@]}")

total=$((resolved + escalated))
if (( total == 0 )); then
  echo "soak: no schema_v2 resolved/escalated events within $SINCE in $AUDIT_DIR" >&2
  exit 1
fi

rate=$(awk -v e="$escalated" -v t="$total" 'BEGIN{printf "%.4f", e/t}')
(( VERBOSE )) && \
  echo "soak: resolved=$resolved escalated=$escalated total=$total rate=$rate threshold=$THRESHOLD"

if ! awk -v r="$rate" -v th="$THRESHOLD" 'BEGIN{ exit !(r+0 < th+0) }'; then
  echo "soak FAIL: false-escalate rate $rate >= $THRESHOLD (resolved=$resolved escalated=$escalated)"
  exit 1
fi

echo "soak PASS: false-escalate rate $rate < $THRESHOLD (resolved=$resolved escalated=$escalated)"
exit 0
