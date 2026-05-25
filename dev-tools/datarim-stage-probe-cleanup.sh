#!/usr/bin/env bash
# datarim-stage-probe-cleanup.sh — remove the Datarim stage-probe harness dir.
#
# Idempotent: exit 0 whether or not /tmp/datarim-test-{TASK-ID}/ existed.
# Symlink-safe: refuses to follow symlinks targeting outside /tmp.
#
# Invoked by /dr-archive when wish phase2-harness-axes-a-b-c-d closure is
# required (Axis D — cleanup invariant).
#
# Usage:
#   dev-tools/datarim-stage-probe-cleanup.sh <TASK-ID>
#
# Exit codes:
#   0  removed (or nothing to remove)
#   1  symlink refused (T2 mitigation)
#   2  TASK-ID regex fail

set -euo pipefail

TASK_ID="${1:-}"

if ! [[ "$TASK_ID" =~ ^[A-Z]+-[0-9]{4,}$ ]]; then
    printf 'cleanup: bad TASK-ID %q\n' "$TASK_ID" >&2
    exit 2
fi

DIR="/tmp/datarim-test-${TASK_ID}"

if [ -L "$DIR" ]; then
    printf 'cleanup: refuse symlink %s (T2 mitigation)\n' "$DIR" >&2
    exit 1
fi

if [ -d "$DIR" ]; then
    rm -rf -- "$DIR"
    printf 'ok: removed %s\n' "$DIR"
else
    printf 'ok: %s did not exist (no-op)\n' "$DIR"
fi
