#!/usr/bin/env bash
#
# measure-invocation-token-cost.sh — per-task token-cost aggregation from the
# coworker JSONL log.
#
# Reads `${XDG_STATE_HOME:-$HOME/.local/state}/coworker/log/<YYYY-MM-DD>.jsonl`
# (daily-rotated, OpenTelemetry-style dotted keys), filters records by
# `coworker.task_id`, sums `gen_ai.usage.input_tokens` +
# `gen_ai.usage.output_tokens`. Output JSON.
#
# Inputs:
#   --task <ID>                 Mandatory. Task identifier (regex ^[A-Z]+-[0-9]+$).
#   --since <duration|date>     Optional. Default 7d. Accepts:
#                                 NNd  → mtime ≥ now() - NNd
#                                 YYYY-MM-DD → daily file ≥ that date
#   --output-format {json,text} Optional. Default json.
#
# Output: JSON with task_id, since, total_tokens (input+output), input_tokens,
# output_tokens, total_cost_usd, record_count, provider_breakdown.
#
# Exit code: 0 always (gate decision is logged, not enforced).
#            2 on argparse / missing input.

# strict-mode rationale: -e omitted intentionally. Contract: "exit code 0 always; exit 2 on
# argparse errors only." Under -e, a python3 crash (e.g. unexpected log format, OS error) would
# exit non-zero before reaching the explicit 'exit 0' at EOF, violating the "gate is logged not
# enforced" guarantee. The python heredoc handles all I/O errors via try/except. Omitting -e
# preserves the exit-0-always invariant. -u and pipefail are retained.
set -uo pipefail

TASK_ID=""
SINCE="7d"
OUTPUT_FORMAT="json"

while [ $# -gt 0 ]; do
    case "$1" in
        --task)
            shift
            [ $# -gt 0 ] || { echo "measure-invocation-token-cost: --task requires value" >&2; exit 2; }
            TASK_ID="$1"; shift ;;
        --since)
            shift
            [ $# -gt 0 ] || { echo "measure-invocation-token-cost: --since requires value" >&2; exit 2; }
            SINCE="$1"; shift ;;
        --output-format)
            shift
            [ $# -gt 0 ] || { echo "measure-invocation-token-cost: --output-format requires value" >&2; exit 2; }
            OUTPUT_FORMAT="$1"; shift ;;
        --help|-h)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "measure-invocation-token-cost: unknown arg: $1" >&2
            exit 2 ;;
    esac
done

if [ -z "$TASK_ID" ]; then
    echo "measure-invocation-token-cost: --task <TASK-ID> required" >&2
    exit 2
fi
if ! printf '%s' "$TASK_ID" | grep -qE '^[A-Z]+-[0-9]+$'; then
    echo "measure-invocation-token-cost: invalid task-id (regex ^[A-Z]+-[0-9]+\$): $TASK_ID" >&2
    exit 2
fi

case "$OUTPUT_FORMAT" in
    json|text) ;;
    *) echo "measure-invocation-token-cost: invalid --output-format ($OUTPUT_FORMAT)" >&2; exit 2 ;;
esac

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/coworker/log"
if [ ! -d "$LOG_DIR" ]; then
    # No log dir → return zero-state JSON, exit 0
    cat <<EOF
{"task_id": "$TASK_ID", "since": "$SINCE", "total_tokens": 0, "input_tokens": 0, "output_tokens": 0, "total_cost_usd": 0.0, "record_count": 0, "provider_breakdown": {}, "note": "log dir not found at $LOG_DIR"}
EOF
    exit 0
fi

# Stream all JSONL files matching --since filter through python aggregator.
python3 - "$TASK_ID" "$SINCE" "$LOG_DIR" "$OUTPUT_FORMAT" <<'PYEOF'
import json
import os
import re
import sys
from datetime import datetime, timedelta

task_id = sys.argv[1]
since = sys.argv[2]
log_dir = sys.argv[3]
fmt = sys.argv[4]

cutoff = None
if re.fullmatch(r"\d+d", since):
    days = int(since[:-1])
    cutoff = datetime.now() - timedelta(days=days)
elif re.fullmatch(r"\d{4}-\d{2}-\d{2}", since):
    cutoff = datetime.strptime(since, "%Y-%m-%d")
else:
    print(f"invalid --since value: {since}", file=sys.stderr)
    sys.exit(2)

files = []
for name in sorted(os.listdir(log_dir)):
    if not name.endswith(".jsonl"):
        continue
    m = re.fullmatch(r"(\d{4}-\d{2}-\d{2})\.jsonl", name)
    if not m:
        continue
    file_date = datetime.strptime(m.group(1), "%Y-%m-%d")
    if file_date < cutoff.replace(hour=0, minute=0, second=0, microsecond=0):
        continue
    files.append(os.path.join(log_dir, name))

input_tokens = 0
output_tokens = 0
cost_usd = 0.0
record_count = 0
provider_breakdown = {}

for path in files:
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                if rec.get("coworker.task_id") != task_id:
                    continue
                sub = rec.get("coworker.subcommand", "")
                if sub not in ("ask", "write"):
                    continue
                ti = int(rec.get("gen_ai.usage.input_tokens", 0) or 0)
                to = int(rec.get("gen_ai.usage.output_tokens", 0) or 0)
                cu = float(rec.get("coworker.cost_usd", 0.0) or 0.0)
                provider = rec.get("gen_ai.system", "unknown")
                input_tokens += ti
                output_tokens += to
                cost_usd += cu
                record_count += 1
                pb = provider_breakdown.setdefault(provider, {
                    "input_tokens": 0,
                    "output_tokens": 0,
                    "cost_usd": 0.0,
                    "record_count": 0,
                })
                pb["input_tokens"] += ti
                pb["output_tokens"] += to
                pb["cost_usd"] += cu
                pb["record_count"] += 1
    except OSError:
        continue

result = {
    "task_id": task_id,
    "since": since,
    "total_tokens": input_tokens + output_tokens,
    "input_tokens": input_tokens,
    "output_tokens": output_tokens,
    "total_cost_usd": round(cost_usd, 6),
    "record_count": record_count,
    "provider_breakdown": provider_breakdown,
}

if fmt == "json":
    print(json.dumps(result, ensure_ascii=False, indent=2))
else:
    print(f"task_id:         {result['task_id']}")
    print(f"since:           {result['since']}")
    print(f"total_tokens:    {result['total_tokens']}")
    print(f"input_tokens:    {result['input_tokens']}")
    print(f"output_tokens:   {result['output_tokens']}")
    print(f"total_cost_usd:  ${result['total_cost_usd']}")
    print(f"record_count:    {result['record_count']}")
    for provider, pb in result["provider_breakdown"].items():
        print(f"  [{provider}] tokens={pb['input_tokens']+pb['output_tokens']} "
              f"cost=${round(pb['cost_usd'], 6)} records={pb['record_count']}")
PYEOF
exit 0
