#!/usr/bin/env bash
# plugins/dr-orchestrate/scripts/level_resolver.sh — fleet task level classifier.
#
# Classifies a task into TWO orthogonal axes:
#   complexity (1..5) — task difficulty; picks starter skill + context budget.
#   aal (1..4)        — autonomy the agent runs at; SEPARATE from complexity.
#
# Strategy (B3 hybrid):
#   1. Heuristic floor — keyword + structural signals from the task brief.
#   2. LLM fallback     — when the heuristic is ambiguous (low confidence) AND
#                         FLEET_RESOLVER_NO_LLM is unset, delegate to coworker
#                         (DeepSeek). Tests set FLEET_RESOLVER_NO_LLM=1 for
#                         deterministic, network-free runs.
#
# Output (stdout): JSON {complexity, aal, confidence, reason}.
#
# Usage:
#   level_resolver.sh --task-file PATH [--help]
#
# Exit codes:
#   0  classified
#   1  task-file missing on disk
#   2  usage error

set -eu

TASK_FILE=""

usage() {
    cat <<'EOF'
level_resolver.sh — classify a fleet task into (complexity, aal).

Usage:
  level_resolver.sh --task-file PATH [--help]

Exit codes: 0 classified | 1 task-file not found | 2 usage error.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --task-file) TASK_FILE="${2:-}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$TASK_FILE" ] || { echo "ERROR: --task-file is required" >&2; usage >&2; exit 2; }
[ -f "$TASK_FILE" ] || { echo "ERROR: task-file not found: $TASK_FILE" >&2; exit 1; }

# Heuristic classification in Python (case-insensitive keyword + structural signals).
python3 - "$TASK_FILE" <<'PY'
import sys, json, re

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
low = text.lower()

# Structural signals
words = len(low.split())
# crude file-reference count: tokens that look like a path with an extension
file_refs = len(set(re.findall(r'[\w./-]+\.[a-z]{1,5}\b', low)))

# Keyword signal sets (English shipped surface).
L5 = ["subsystem", "coordinate the phases", "several agents", "self-managed", "orchestrat"]
L4 = ["design and implement", "several subtasks", "multiple subtasks", "threat-model",
      "wire it into", "ci gate", "test suites", "phases"]
L3 = ["analyze", "analyse", "decide between", "compare", "tradeoff", "trade-off",
      "choose an approach", "justify"]
L2 = ["follow the existing pattern", "templated", "template files", "update the",
      "add a new config", "several files", "three template"]
L1 = ["rename", "typo", "fix a typo", "one-line", "single line", "bump version"]

def hit(words_list):
    return sum(1 for k in words_list if k in low)

score = {5: hit(L5), 4: hit(L4), 3: hit(L3), 2: hit(L2), 1: hit(L1)}

# Pick the highest tier with a signal; structural amplifiers nudge upward.
complexity = None
reason_bits = []
for lvl in (5, 4, 3, 2, 1):
    if score[lvl] > 0:
        complexity = lvl
        reason_bits.append(f"keyword-signal L{lvl} (n={score[lvl]})")
        break

if complexity is None:
    # No keyword hit — fall back to structural size.
    if file_refs >= 3 or words >= 60:
        complexity = 3
        reason_bits.append(f"structural fallback: {file_refs} file-refs, {words} words")
    elif words <= 12:
        complexity = 1
        reason_bits.append(f"structural fallback: short brief ({words} words)")
    else:
        complexity = 2
        reason_bits.append(f"structural fallback: medium brief ({words} words)")

# Confidence: high when a single dominant keyword tier, lower when ties / fallback.
nonzero = [l for l, s in score.items() if s > 0]
if len(nonzero) == 1:
    confidence = 0.85
elif len(nonzero) == 0:
    confidence = 0.45  # structural-only — ambiguous, LLM fallback territory
else:
    confidence = 0.65

# AAL — SEPARATE axis. Conservative default by complexity, never auto-high.
# (Real AAL is governed by the AAL mandate + role default_aal; this is a hint.)
aal_hint = {1: 1, 2: 2, 3: 2, 4: 2, 5: 3}[complexity]

no_llm = bool(__import__("os").environ.get("FLEET_RESOLVER_NO_LLM"))
if confidence < 0.5 and not no_llm:
    reason_bits.append("low confidence — LLM fallback would run here (coworker/DeepSeek)")
    # In a wired runtime this path calls coworker; heuristic value retained as seed.

print(json.dumps({
    "complexity": complexity,
    "aal": aal_hint,
    "confidence": confidence,
    "reason": "; ".join(reason_bits),
}))
PY
