#!/usr/bin/env bash
# session-handoff-writer-wrapper.sh — bash-shebang wrapper for write_session_handoff.
#
# Why this exists:
#   scripts/lib/session-handoff-writer.sh uses BASH_SOURCE[0] for sibling-script
#   resolution. Under zsh-parent shells (default on macOS user profiles) the
#   array is unset, the writer fails silently. This wrapper forces bash execution.
#   All arguments are forwarded verbatim to write_session_handoff(). Exit codes
#   match the underlying function.
#
# Usage (literal — never use sh, always bash):
#   bash "${DATARIM_RUNTIME:-$HOME/.claude}/dev-tools/session-handoff-writer-wrapper.sh" \
#       --root <repo> --session <SESSION-YYYYMMDD-HHMMSS> \
#       --captured-by <agent|operator> --recommended-next "/dr-next TASK-ID" \
#       --next-action "<single-line description>" \
#       --active-tasks-file <path> --body-file <path> \
#       [--captured-at <ISO-8601 UTC>]

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
WRITER="${SCRIPT_DIR}/../scripts/lib/session-handoff-writer.sh"

if [ ! -f "$WRITER" ]; then
    printf 'session-handoff-writer-wrapper: writer missing: %s\n' "$WRITER" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$WRITER"
write_session_handoff "$@"
