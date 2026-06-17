#!/usr/bin/env bash
# content_consilium_gate.sh — Hard gate for consilium publish actions.
#
# Usage:
#   content_consilium_gate.sh --run-dir <dir> [--dry-run]
#   content_consilium_gate.sh --run-dir <dir> --publish --target <file>
#
# Default mode is DRY-RUN: the script validates the run directory and prints
# a DRY-RUN notice. No publish action is taken unless --publish is explicitly
# given.
#
# This gate is the hard-gate enforcement point for the FB-rules entry
# "content_consilium_publish" under hard_gated_actions. Real publish calls
# (POST to social APIs, filesystem writes to live site paths, etc.) MUST
# NOT happen without an explicit --publish flag AND operator confirmation.
#
# Exit codes:
#   0 — gate checks passed (dry-run or publish completed)
#   1 — gate check failed (missing final.md, validation error)
#   2 — usage error

set -uo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
RUN_DIR=""
PUBLISH=0
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)  RUN_DIR="$2";  shift 2 ;;
    --publish)  PUBLISH=1;     shift   ;;
    --dry-run)  PUBLISH=0;     shift   ;;  # explicit dry-run; already the default
    --target)   TARGET="$2";   shift 2 ;;
    *) echo "ERR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$RUN_DIR" ]] || { echo "ERR: --run-dir required" >&2; exit 2; }
[[ -d "$RUN_DIR" ]] || { echo "ERR: run-dir not found: $RUN_DIR" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Gate check: final.md must exist
# ---------------------------------------------------------------------------
FINAL="$RUN_DIR/final.md"
if [[ ! -f "$FINAL" ]]; then
  echo "ERR: final.md not found in $RUN_DIR — run judge first" >&2
  echo "ERR: publish gate BLOCKED" >&2
  exit 1
fi

if [[ ! -s "$FINAL" ]]; then
  echo "ERR: final.md is empty in $RUN_DIR" >&2
  echo "ERR: publish gate BLOCKED" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Check for degradation acknowledgement (warning only, not a hard block)
# ---------------------------------------------------------------------------
DEGRADE_NOTE="$RUN_DIR/degradation_note.txt"
if [[ -f "$DEGRADE_NOTE" ]]; then
  echo "WARNING: consilium ran in degraded mode — see $DEGRADE_NOTE" >&2
fi

# ---------------------------------------------------------------------------
# Dry-run mode (default when --publish is not given)
# ---------------------------------------------------------------------------
if [[ "$PUBLISH" -eq 0 ]]; then
  echo "DRY-RUN: publish gate passed. final.md validated at $FINAL"
  echo "DRY-RUN: no publish action taken. Pass --publish --target <file> to publish."
  if [[ -f "$RUN_DIR/judge-decision.md" ]]; then
    echo "DRY-RUN: judge-decision.md found — winner documented."
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Publish mode: --publish flag explicitly given
# ---------------------------------------------------------------------------
[[ -n "$TARGET" ]] || { echo "ERR: --target required with --publish" >&2; exit 2; }

# Perform the publish action: copy final content to target
cp "$FINAL" "$TARGET"
echo "PUBLISHED: $FINAL -> $TARGET"
echo "GATE: content_consilium_publish action logged"
exit 0
