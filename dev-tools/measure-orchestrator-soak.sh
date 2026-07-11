#!/usr/bin/env bash
# measure-orchestrator-soak.sh — V-AC-22 soak verdict gate for /dr-orchestrate.
# Computes refined false-escalation rate from schema_version=2 audit events:
#
#   false_escalate_rate =
#       escalated WHERE expected_outcome=="resolved" AND outcome != "blocked_decision_cooldown"
#     / events   WHERE expected_outcome=="resolved" AND outcome != "blocked_decision_cooldown"
#
# Events without expected_outcome (null/"") are excluded from the metric —
# backward-compatible with older audit files that pre-date the label field.
# Designed escalations (expected_outcome=="escalated") are never false-positives
# and are not counted. blocked_decision_cooldown entries are excluded from both
# numerator and denominator.
#
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

shopt -s nullglob
files=( "$AUDIT_DIR"/audit-*.jsonl )
if (( ${#files[@]} == 0 )); then
  echo "soak: no audit files in $AUDIT_DIR" >&2
  exit 1
fi

# Single jq -s (slurp) invocation over ALL audit files instead of one jq
# subprocess per field per line (previous ~4 forks/line caused a 7-minute
# stalled-pipe on large soak logs — V-AC-24.4 / TUNE-0242). `-R -n inputs`
# reads raw lines across every file argument in order (same combined-stream
# semantics as the old `cat "${files[@]}"`); `fromjson?` silently drops
# empty/malformed lines exactly like the old `[[ -n "$line" ]] || continue`
# guard. `fromdateiso8601` replaces the GNU/BSD `date` fallback chain for
# the same strict `%Y-%m-%dT%H:%M:%SZ` UTC format, defaulting unparsable
# timestamps to epoch 0 (always outside the window) via `try/catch`.
read -r resolved escalated < <(
  jq -R -r -n --argjson cutoff "$cutoff_ts" '
    [inputs | fromjson?] as $events
    | ($events | map(select(.schema_version == 2))) as $v2
    | ($v2 | map(select((.timestamp // .ts // "") != ""))) as $timed
    | ($timed | map(. + {_ts: ((.timestamp // .ts) | try fromdateiso8601 catch 0)})) as $tsed
    | ($tsed | map(select(._ts >= $cutoff))) as $windowed
    | ($windowed | map(select((.expected_outcome // "") == "resolved"))) as $expected_resolved
    | ($expected_resolved | map(select((.outcome // "") != "blocked_decision_cooldown"))) as $filtered
    | ($filtered | map(select(.outcome == "resolved")) | length) as $r
    | ($filtered | map(select(.outcome == "escalated")) | length) as $e
    | "\($r) \($e)"
  ' "${files[@]}"
)

total=$((resolved + escalated))
if (( total == 0 )); then
  echo "soak: no schema_v2 resolved-expected events within $SINCE in $AUDIT_DIR" >&2
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
