#!/usr/bin/env bash
# scan-id-across-instances.sh — advisory cross-instance task-ID collision scan.
#
# Usage:
#   scan-id-across-instances.sh <TASK-ID> <SCAN-ROOT> [<SELF-DATARIM-DIR>]
#
# /dr-init selects and validates a task ID against ONE resolved datarim/
# instance. A fleet can hold several datarim/ instances (a workspace root plus
# nested project instances); universal area prefixes span them all, so the same
# ID string can be claimed cross-instance for different work without /dr-init
# noticing. This helper scans sibling backlog.md / tasks.md files under a bounded
# scan root and reports any that already claim <TASK-ID> as an entry line.
#
# Contract:
#   stdout      one "path:lineno:line" per cross-instance entry-line match;
#               nothing when clean.
#   stderr      a one-line scope banner (scan root + files scanned) for
#               transparency about the bound; validation errors.
#   exit code   0 on any successful scan (match OR no match) — this probe is
#               ADVISORY and never gates /dr-init; 1 on usage/validation error.
#
# Match is anchored to an entry line ("^- <ID> ...") so prose mentions are
# ignored. The current instance (SELF-DATARIM-DIR, when supplied) is excluded —
# it is already covered by the in-instance Step-4 probe. Framework template
# source (*/code/datarim/*), .git, node_modules and .worktrees are pruned.
#
# Security: S1 strict mode, regex-validated args, all expansions quoted, no eval,
# bounded find with explicit prunes. Read-only — no network, no writes.

set -euo pipefail

# ── argument validation ──────────────────────────────────────────────────────

if [[ $# -lt 2 ]]; then
    echo "Usage: scan-id-across-instances.sh <TASK-ID> <SCAN-ROOT> [<SELF-DATARIM-DIR>]" >&2
    exit 1
fi

TASK_ID="$1"
SCAN_ROOT="$2"
SELF_DATARIM_DIR="${3:-}"

# TASK-ID: uppercase letter + 1–9 uppercase letters/digits, dash, exactly 4 digits (Security S1)
if ! [[ "$TASK_ID" =~ ^[A-Z][A-Z0-9]{1,9}-[0-9]{4}$ ]]; then
    echo "ERROR: invalid TASK-ID '${TASK_ID}' — expected PREFIX-NNNN (prefix starts with an uppercase letter and contains 2–10 uppercase letters/digits; exactly 4 trailing digits)" >&2
    exit 1
fi

if [[ ! -d "$SCAN_ROOT" ]]; then
    echo "ERROR: SCAN-ROOT '${SCAN_ROOT}' does not exist or is not a directory" >&2
    exit 1
fi

# ── bounded discovery of sibling instance backlogs / task lists ──────────────
# Prune heavy / irrelevant trees; collect backlog.md + tasks.md that live under
# a */datarim/* path but NOT under a framework */code/datarim/* template tree.

scanned=0

# Anchored entry-line pattern: the ID at the start of a list item, followed by a
# space or end-of-line. ASCII-only (no non-ASCII separator literal) so the
# shipped shell surface stays English-only, while still ignoring prose mentions.
pattern="^- ${TASK_ID}([[:space:]]|\$)"

while IFS= read -r -d '' f; do
    # Skip the current instance — already covered by the in-instance probe.
    if [[ -n "$SELF_DATARIM_DIR" && ( "$f" == "$SELF_DATARIM_DIR"/* || "${f%/*}" == "$SELF_DATARIM_DIR" ) ]]; then
        continue
    fi
    scanned=$(( scanned + 1 ))
    # -H forces filename prefix even on a single file; ERE for the anchor.
    grep -HnE "$pattern" "$f" 2>/dev/null || true
done < <(
    find "$SCAN_ROOT" \
        \( -type d \( -name .git -o -name node_modules -o -name .worktrees \) -prune \) -o \
        \( -type f \( -name backlog.md -o -name tasks.md \) \
           -path '*/datarim/*' -not -path '*/code/datarim/*' -print0 \)
)

# ── scope banner (transparency about the bound) ──────────────────────────────
echo "scan-id-across-instances: scanned ${scanned} sibling instance file(s) under ${SCAN_ROOT} for ${TASK_ID}" >&2

exit 0
