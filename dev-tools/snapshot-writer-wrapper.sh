#!/usr/bin/env bash
# snapshot-writer-wrapper.sh — bash-shebang wrapper around write_stage_snapshot.
#
# Why this exists:
#   scripts/lib/snapshot-writer.sh uses BASH_SOURCE[0] for sibling-script
#   resolution. Under zsh-parent shells (default on macOS user profiles) the
#   array is unset, the writer fails silently with:
#     `BASH_SOURCE[0]: parameter not set`
#     `no such file or directory: <cwd>/plugin-system.sh`
#     `command not found: write_stage_snapshot`
#   and the snapshot is never written. Agents invoking via the Bash tool
#   inherit the user's login shell, so the failure is invisible without
#   explicit stderr capture.
#
# This wrapper forces bash execution. All arguments forward verbatim to
# write_stage_snapshot(). Exit codes match the underlying function.
#
# Usage:
#   bash dev-tools/snapshot-writer-wrapper.sh \
#       --root <repo> --task <ID> --stage <stage> --command </dr-*> \
#       --captured-by <agent|human> --recommended-next "/dr-*" \
#       --options-file <path> --body-file <path> [--captured-at <ISO>]

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
WRITER="${SCRIPT_DIR}/../scripts/lib/snapshot-writer.sh"

if [ ! -f "$WRITER" ]; then
    printf 'snapshot-writer-wrapper: writer missing: %s\n' "$WRITER" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$WRITER"
write_stage_snapshot "$@"
