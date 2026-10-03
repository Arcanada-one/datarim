#!/usr/bin/env bash
#
# measure-prospective-rate.sh — aggregate `verification_outcome` blocks from
# archive YAML frontmatters and compute the gap-catch rate per N tasks.
#
# Reads `archive-*.md` files under `documentation/archive/**/`, parses YAML
# frontmatter, extracts the `verification_outcome` block:
#   verification_outcome:
#     caught_by_verify: <int>
#     missed_by_verify: <int>
#     false_positive: <int>
#     n_a: <bool>
#     dogfood_window: <window-id>
#
# Inputs:
#   --since <YYYY-MM-DD>      Mandatory. Lower bound on archive mtime.
#   --archive-root <path>     Optional. Default: documentation/archive/
#   --tag-field <name>        Optional. Default: verification_outcome.
#                             Override is for experimental schema renames.
#
# Output: JSON with since, total_tasks (with verification_outcome), n_a count,
# sum_caught/missed/false_positive, rate_per_5_tasks, rate_per_10_tasks,
# decision_hint.
#
# Exit code: 0 always. 2 on argparse error.

# strict-mode rationale: -e omitted intentionally. Contract: "exit code 0 always; 2 on argparse
# error." Under -e, a python3 crash on malformed frontmatter or filesystem I/O would exit
# non-zero before reaching the explicit 'exit 0' at EOF, violating the "gate logged not enforced"
# invariant. The python heredoc handles all errors via try/except and ValueError guards. Omitting
# -e preserves exit-0-always. -u and pipefail are retained to catch unbound vars and pipe errors.
set -uo pipefail

SINCE=""
ARCHIVE_ROOT="documentation/archive"
TAG_FIELD="verification_outcome"
VERIFY_DIR="datarim/qa"

while [ $# -gt 0 ]; do
    case "$1" in
        --since)
            shift
            [ $# -gt 0 ] || { echo "measure-prospective-rate: --since requires value" >&2; exit 2; }
            SINCE="$1"; shift ;;
        --archive-root)
            shift
            [ $# -gt 0 ] || { echo "measure-prospective-rate: --archive-root requires value" >&2; exit 2; }
            ARCHIVE_ROOT="$1"; shift ;;
        --tag-field)
            shift
            [ $# -gt 0 ] || { echo "measure-prospective-rate: --tag-field requires value" >&2; exit 2; }
            TAG_FIELD="$1"; shift ;;
        --verify-dir)
            shift
            [ $# -gt 0 ] || { echo "measure-prospective-rate: --verify-dir requires value" >&2; exit 2; }
            VERIFY_DIR="$1"; shift ;;
        --help|-h)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "measure-prospective-rate: unknown arg: $1" >&2
            exit 2 ;;
    esac
done

if [ -z "$SINCE" ]; then
    echo "measure-prospective-rate: --since <YYYY-MM-DD> required" >&2
    exit 2
fi
if ! printf '%s' "$SINCE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    echo "measure-prospective-rate: invalid --since (expected YYYY-MM-DD): $SINCE" >&2
    exit 2
fi

# Note: missing archive-root is handled inside python (os.walk returns empty
# iterator). The bash early-exit branch was removed so the verify-dir walk
# runs even when archive-root is absent — otherwise callers using only
# verify-dir would see a truncated JSON shape missing the per_mode_rates
# fields.

python3 - "$SINCE" "$ARCHIVE_ROOT" "$TAG_FIELD" "$VERIFY_DIR" <<'PYEOF'
import json
import os
import re
import sys
from datetime import datetime

since = sys.argv[1]
archive_root = sys.argv[2]
tag_field = sys.argv[3]
verify_dir = sys.argv[4]

since_dt = datetime.strptime(since, "%Y-%m-%d")
since_ts = since_dt.timestamp()

# Find archive-*.md files under archive_root recursively, mtime ≥ since.
archive_files = []
for root, _dirs, files in os.walk(archive_root):
    for name in files:
        if not name.startswith("archive-") or not name.endswith(".md"):
            continue
        path = os.path.join(root, name)
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if mtime < since_ts:
            continue
        archive_files.append(path)

total_tasks = 0
n_a_count = 0
sum_caught = 0
sum_missed = 0
sum_fp = 0
window_breakdown = {}

# Parse YAML frontmatter (between --- markers) by simple line walk.
fm_re = re.compile(r"^---\s*$")
field_re = re.compile(r"^\s*([A-Za-z0-9_]+)\s*:\s*(.*)$")

for path in archive_files:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            content = fh.read()
    except OSError:
        continue

    # Extract frontmatter
    if not content.startswith("---"):
        continue
    end_match = re.search(r"\n---\s*\n", content)
    if not end_match:
        continue
    fm = content[:end_match.start()]

    # Walk the frontmatter looking for tag_field block
    in_block = False
    block_indent = None
    block_data = {}
    for raw in fm.split("\n"):
        if not in_block:
            m = re.match(r"^(\s*)" + re.escape(tag_field) + r"\s*:\s*$", raw)
            if m:
                in_block = True
                block_indent = len(m.group(1))
                continue
        else:
            if raw.strip() == "":
                continue
            cur_indent = len(raw) - len(raw.lstrip())
            if cur_indent <= block_indent:
                in_block = False
                continue
            fm2 = field_re.match(raw)
            if fm2:
                key = fm2.group(1)
                val = fm2.group(2).strip()
                if val.startswith("#"):
                    val = ""
                # Strip inline comments
                val = re.sub(r"\s+#.*$", "", val)
                block_data[key] = val

    if not block_data:
        continue

    total_tasks += 1
    n_a_raw = block_data.get("n_a", "false").strip().lower()
    is_na = n_a_raw in ("true", "yes", "1")
    if is_na:
        n_a_count += 1
        continue

    try:
        sum_caught += int(block_data.get("caught_by_verify", "0") or "0")
        sum_missed += int(block_data.get("missed_by_verify", "0") or "0")
        sum_fp += int(block_data.get("false_positive", "0") or "0")
    except ValueError:
        pass

    window = block_data.get("dogfood_window", "").strip().strip("\"'")
    if window:
        wb = window_breakdown.setdefault(window, {
            "tasks": 0,
            "caught": 0,
            "missed": 0,
            "false_positive": 0,
        })
        wb["tasks"] += 1
        try:
            wb["caught"] += int(block_data.get("caught_by_verify", "0") or "0")
            wb["missed"] += int(block_data.get("missed_by_verify", "0") or "0")
            wb["false_positive"] += int(block_data.get("false_positive", "0") or "0")
        except ValueError:
            pass

scoring_tasks = total_tasks - n_a_count
if scoring_tasks > 0:
    rate_5 = round((sum_caught / scoring_tasks) * 5, 4)
    rate_10 = round((sum_caught / scoring_tasks) * 10, 4)
else:
    rate_5 = 0.0
    rate_10 = 0.0

# Per-mode peer_review distribution from datarim/qa/verify-*.md.
# Walks audit-log files since SINCE; counts `peer_review_mode: <X>` field
# occurrences (per-finding tag) and emits per-mode rates per scoring task.
mode_counts = {
    "cross_vendor": 0,
    "cross_claude_family": 0,
    "same_model_isolated": 0,
}
verify_files_seen = 0
verify_mode_re = re.compile(r"peer_review_mode:\s*([a-z_]+)")
if os.path.isdir(verify_dir):
    for root, _dirs, files in os.walk(verify_dir):
        for name in files:
            if not name.startswith("verify-") or not name.endswith(".md"):
                continue
            path = os.path.join(root, name)
            try:
                mtime = os.path.getmtime(path)
            except OSError:
                continue
            if mtime < since_ts:
                continue
            verify_files_seen += 1
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    body = fh.read()
            except OSError:
                continue
            for m in verify_mode_re.finditer(body):
                mode = m.group(1)
                if mode in mode_counts:
                    mode_counts[mode] += 1

# Per-mode rates: count / scoring_tasks (parallel to caught_per_5_tasks).
# When scoring_tasks=0 the absolute count is exposed (rate undefined → 0.0).
def per_mode_rate(count, denom):
    return round(count / denom, 4) if denom > 0 else 0.0

cross_vendor_rate = per_mode_rate(mode_counts["cross_vendor"], scoring_tasks)
cross_claude_family_rate = per_mode_rate(mode_counts["cross_claude_family"], scoring_tasks)
same_model_isolated_rate = per_mode_rate(mode_counts["same_model_isolated"], scoring_tasks)

if scoring_tasks == 0:
    decision_hint = "dogfood_window not yet populated"
elif rate_5 >= 1.0:
    decision_hint = "spawn automated post-step hook (rate ≥1 per 5 tasks)"
elif rate_10 >= 1.0:
    decision_hint = "reduced scope ship (1 per 10 ≤ rate < 1 per 5)"
else:
    decision_hint = "kill (rate < 1 per 10)"

result = {
    "since": since,
    "archive_root": archive_root,
    "tag_field": tag_field,
    "verify_dir": verify_dir,
    "total_tasks": total_tasks,
    "n_a": n_a_count,
    "scoring_tasks": scoring_tasks,
    "sum_caught": sum_caught,
    "sum_missed": sum_missed,
    "sum_false_positive": sum_fp,
    "rate_per_5_tasks": rate_5,
    "rate_per_10_tasks": rate_10,
    "decision_hint": decision_hint,
    "dogfood_window_breakdown": window_breakdown,
    "verify_files_seen": verify_files_seen,
    "peer_review_mode_counts": mode_counts,
    "cross_vendor_rate": cross_vendor_rate,
    "cross_claude_family_rate": cross_claude_family_rate,
    "same_model_isolated_rate": same_model_isolated_rate,
}
print(json.dumps(result, ensure_ascii=False, indent=2))
PYEOF
exit 0
