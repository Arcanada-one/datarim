#!/usr/bin/env bash
# datarim-stage-probe-init.sh — initialise the Datarim stage-probe harness.
#
# Creates /tmp/datarim-test-{TASK-ID}/ with mode 0700 and seeds payload.txt +
# empty journal.md. While this directory exists, every write_stage_snapshot
# call for the same TASK-ID will append a journal line documenting whether the
# operator-visible response carried the Stage Header and CTA footer.
#
# Idempotent: re-running on an existing harness directory leaves it intact and
# appends a fresh init line to journal.md.
#
# Cleanup is the caller's responsibility — typically /dr-archive invokes
# datarim-stage-probe-cleanup.sh on the same TASK-ID.
#
# Usage:
#   dev-tools/datarim-stage-probe-init.sh <TASK-ID>
#
# Exit codes:
#   0  ok (created or already existed)
#   1  symlink refused (T2 mitigation) or IO failure
#   2  TASK-ID regex fail

set -euo pipefail

TASK_ID="${1:-}"

if ! [[ "$TASK_ID" =~ ^[A-Z]+-[0-9]{4,}$ ]]; then
    printf 'init: bad TASK-ID %q (expected ^[A-Z]+-[0-9]{4,}$)\n' "$TASK_ID" >&2
    exit 2
fi

DIR="/tmp/datarim-test-${TASK_ID}"

if [ -L "$DIR" ]; then
    printf 'init: refuse symlink %s (T2 mitigation)\n' "$DIR" >&2
    exit 1
fi

if [ ! -d "$DIR" ]; then
    mkdir -p "$DIR"
fi
chmod 0700 "$DIR"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\n' "$NOW" > "$DIR/payload.txt"
: >> "$DIR/journal.md"
printf 'init · %s · TASK-ID=%s\n' "$NOW" "$TASK_ID" >> "$DIR/journal.md"

printf 'ok: harness ready at %s\n' "$DIR"
