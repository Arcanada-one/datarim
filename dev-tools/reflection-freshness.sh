#!/usr/bin/env bash
# reflection-freshness.sh — decide whether a task's reflection document is fresh
# relative to the compliance report it was based on.
#
# A reflection (datarim/reflection/reflection-<ID>.md) is stamped at /dr-compliance
# time with `reflection_basis: <16-hex>` in its YAML frontmatter — the truncated
# sha256 of the compliance report it summarises. At /dr-archive Step 0.5 this script
# recomputes that hash from the CURRENT compliance report and compares.
#
# Four-branch decision (exit code is the contract):
#   exit 1 = regenerate  — reflection file ABSENT
#   exit 1 = regenerate  — reflection present but `reflection_basis` field ABSENT
#   exit 0 = reuse       — basis present AND matches current compliance report
#   exit 1 = regenerate  — basis present but MISMATCHES current compliance report
# The two absent cases are distinct code paths so the mandatory-reflection
# guarantee cannot be bypassed by conflating "no file" with "no field".
#
# --emit-basis <report>  prints the 16-hex basis for <report> and exits 0
#                        (used by /dr-compliance to stamp the reflection).
#
# Usage:
#   reflection-freshness.sh --task <ID> --root <repo-root>
#   reflection-freshness.sh --emit-basis <compliance-report-path>
#
# Exit: 0 reuse / emit-ok | 1 regenerate | 2 usage error

set -euo pipefail

TASK=""
ROOT=""
EMIT_REPORT=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --task) TASK="${2:-}"; shift 2 ;;
        --task=*) TASK="${1#--task=}"; shift ;;
        --root) ROOT="${2:-}"; shift 2 ;;
        --root=*) ROOT="${1#--root=}"; shift ;;
        --emit-basis) EMIT_REPORT="${2:-}"; shift 2 ;;
        --emit-basis=*) EMIT_REPORT="${1#--emit-basis=}"; shift ;;
        -h|--help)
            sed -n '2,28p' "$0"; exit 0 ;;
        *) echo "ERROR: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

# sha256 helper — GNU sha256sum first, BSD shasum fallback. Prints 16-hex prefix.
hash16() {
    local f="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$f" | cut -c1-16
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$f" | cut -c1-16
    else
        echo "ERROR: neither sha256sum nor shasum available" >&2
        exit 2
    fi
}

# --emit-basis mode ---------------------------------------------------------
if [ -n "$EMIT_REPORT" ]; then
    if [ ! -f "$EMIT_REPORT" ]; then
        echo "ERROR: compliance report not found: $EMIT_REPORT" >&2
        exit 2
    fi
    hash16 "$EMIT_REPORT"
    exit 0
fi

# freshness-check mode ------------------------------------------------------
if [ -z "$TASK" ] || [ -z "$ROOT" ]; then
    echo "ERROR: --task and --root are required (or use --emit-basis <report>)" >&2
    exit 2
fi

# Validate task id shape (Security S1 — untrusted input). Allow compound suffixes.
case "$TASK" in
    [A-Z][A-Z0-9]*-[0-9][0-9][0-9][0-9]*) : ;;
    *) echo "ERROR: invalid task id '$TASK'" >&2; exit 2 ;;
esac

REFLECTION="$ROOT/datarim/reflection/reflection-$TASK.md"
REPORT="$ROOT/datarim/reports/compliance-report-$TASK.md"

# Branch 1: reflection file absent -> regenerate.
if [ ! -f "$REFLECTION" ]; then
    echo "regenerate: reflection file absent ($REFLECTION)"
    exit 1
fi

# Read stored basis from frontmatter (first matching line only).
STORED_BASIS="$(grep -m1 -E '^reflection_basis:[[:space:]]*' "$REFLECTION" 2>/dev/null \
    | sed -E 's/^reflection_basis:[[:space:]]*"?([0-9a-f]+)"?[[:space:]]*$/\1/' || true)"

# Branch 2: field absent -> regenerate (DISTINCT path from branch 1).
if [ -z "$STORED_BASIS" ]; then
    echo "regenerate: reflection_basis field absent in $REFLECTION"
    exit 1
fi

# No compliance report to compare against -> treat as stale (regenerate).
if [ ! -f "$REPORT" ]; then
    echo "regenerate: compliance report absent ($REPORT) — cannot confirm freshness"
    exit 1
fi

CURRENT_BASIS="$(hash16 "$REPORT")"

# Branch 3: match -> reuse.
if [ "$STORED_BASIS" = "$CURRENT_BASIS" ]; then
    echo "reuse: reflection is current (basis $STORED_BASIS)"
    exit 0
fi

# Branch 4: mismatch -> regenerate.
echo "regenerate: reflection stale (stored $STORED_BASIS != current $CURRENT_BASIS)"
exit 1
