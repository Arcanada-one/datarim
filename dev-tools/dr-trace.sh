#!/usr/bin/env bash
# dr-trace.sh — spec-traceability coverage report (R5).
#
# Read-only. Builds the D-REQ <-> V-AC coverage graph for a task and prints a
# compact report in five buckets:
#   covered             D-REQ referenced by >=1 resolving V-AC Covers line
#   uncovered           declared D-REQ referenced by no V-AC (and not deferred)
#   dangling            Covers references to a non-existent D-REQ
#   orphaned            declared D-REQ with no V-AC reference (alias surface of uncovered)
#   explicitly_deferred D-REQ whose declaration is marked deferred
#
# Usage:
#   dr-trace.sh --task <ID> [--root <path>] [--format json|text] [--strict]
#
# Exit: 0 (report, not a gate). With --strict: exit 1 when uncovered OR dangling
#       is non-empty. 2 = usage/configuration error.
# Contract: docs/validator-contract.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="${SCRIPT_DIR}/../scripts/lib/spec-graph.sh"

if [ ! -f "$LIB" ]; then
    echo "ERROR: shared lib not found: $LIB" >&2
    exit 2
fi
# shellcheck source=scripts/lib/spec-graph.sh
. "$LIB"

# dr-trace adds one local flag (--strict) on top of the shared vocabulary.
STRICT=0
ARGS=()
for a in "$@"; do
    if [ "$a" = "--strict" ]; then STRICT=1; else ARGS+=("$a"); fi
done

if [ "${#ARGS[@]}" -gt 0 ]; then
    parse_common_flags "${ARGS[@]}"
else
    parse_common_flags
fi
if [ "${#SPEC_REMAINING_ARGS[@]}" -gt 0 ]; then
    usage_die "unexpected argument: ${SPEC_REMAINING_ARGS[0]}"
fi

[ -n "$SPEC_TASK" ] || usage_die "--task <ID> is required"

ROOT="${SPEC_ROOT:-$PWD}"
[ -d "$ROOT" ] || usage_die "root not found: $ROOT"

DATARIM_ROOT=""
search="$ROOT"
while [ "$search" != "/" ] && [ -n "$search" ]; do
    if [ -d "$search/datarim" ]; then DATARIM_ROOT="$search/datarim"; break; fi
    search="$(dirname "$search")"
done
[ -n "$DATARIM_ROOT" ] || usage_die "datarim/ not found from $ROOT"

PRD_FILE="$DATARIM_ROOT/prd/PRD-${SPEC_TASK}.md"
[ -f "$PRD_FILE" ] || usage_die "PRD not found for $SPEC_TASK: $PRD_FILE"

# ---------------------------------------------------------------------------
# Collect declared ids, deferred ids, and referenced ids.
# ---------------------------------------------------------------------------

DECLARED="$(collect_d_req "$PRD_FILE" | awk -F'\t' '{print $2}' | sort -u)"

# Deferred: a D-REQ declaration line containing the word "deferred".
DEFERRED="$(grep -nE '^#### D-REQ-[0-9]{2}:.*deferred' "$PRD_FILE" 2>/dev/null \
            | grep -oE "$D_REQ_REF_RE" | sort -u)"

# Referenced + dangling from Covers lines.
REFERENCED=""
DANGLING=""
while IFS=$'\t' read -r _ ref; do
    [ -n "$ref" ] || continue
    REFERENCED="${REFERENCED}${ref}"$'\n'
    if ! printf '%s\n' "$DECLARED" | grep -qx "$ref"; then
        DANGLING="${DANGLING}${ref}"$'\n'
    fi
done < <(collect_covers "$PRD_FILE")
REFERENCED="$(printf '%s' "$REFERENCED" | grep -E "^${D_REQ_REF_RE}$" | sort -u)"
DANGLING="$(printf '%s' "$DANGLING" | grep -E "^${D_REQ_REF_RE}$" | sort -u)"

# Bucket each declared id.
COVERED=""
UNCOVERED=""
ORPHANED=""
if [ -n "$DECLARED" ]; then
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        if printf '%s\n' "$DEFERRED" | grep -qx "$id"; then
            continue   # deferred handled in its own bucket
        fi
        if printf '%s\n' "$REFERENCED" | grep -qx "$id"; then
            COVERED="${COVERED}${id}"$'\n'
        else
            UNCOVERED="${UNCOVERED}${id}"$'\n'
            ORPHANED="${ORPHANED}${id}"$'\n'
        fi
    done <<< "$DECLARED"
fi

COVERED="$(printf '%s' "$COVERED" | grep -E "^${D_REQ_REF_RE}$" | sort -u || true)"
UNCOVERED="$(printf '%s' "$UNCOVERED" | grep -E "^${D_REQ_REF_RE}$" | sort -u || true)"
ORPHANED="$(printf '%s' "$ORPHANED" | grep -E "^${D_REQ_REF_RE}$" | sort -u || true)"

# ---------------------------------------------------------------------------
# Emit.
# ---------------------------------------------------------------------------

json_array() {
    # turn a newline list into a JSON array of strings
    python3 - "$1" <<'PYEOF'
import json, sys
items = [x for x in sys.argv[1].splitlines() if x.strip()]
sys.stdout.write(json.dumps(items))
PYEOF
}

if [ "$SPEC_FORMAT" = "json" ]; then
    printf '{'
    printf '"task":"%s",' "$SPEC_TASK"
    printf '"covered":%s,' "$(json_array "$COVERED")"
    printf '"uncovered":%s,' "$(json_array "$UNCOVERED")"
    printf '"dangling":%s,' "$(json_array "$DANGLING")"
    printf '"orphaned":%s,' "$(json_array "$ORPHANED")"
    printf '"explicitly_deferred":%s' "$(json_array "$DEFERRED")"
    printf '}\n'
else
    echo "Spec-traceability coverage for $SPEC_TASK"
    echo "  covered             : $(printf '%s' "$COVERED" | grep -c . || true)  [$(printf '%s' "$COVERED" | tr '\n' ' ')]"
    echo "  uncovered           : $(printf '%s' "$UNCOVERED" | grep -c . || true)  [$(printf '%s' "$UNCOVERED" | tr '\n' ' ')]"
    echo "  dangling            : $(printf '%s' "$DANGLING" | grep -c . || true)  [$(printf '%s' "$DANGLING" | tr '\n' ' ')]"
    echo "  orphaned            : $(printf '%s' "$ORPHANED" | grep -c . || true)  [$(printf '%s' "$ORPHANED" | tr '\n' ' ')]"
    echo "  explicitly_deferred : $(printf '%s' "$DEFERRED" | grep -c . || true)  [$(printf '%s' "$DEFERRED" | tr '\n' ' ')]"
fi

if [ "$STRICT" -eq 1 ]; then
    n_uncovered="$(printf '%s' "$UNCOVERED" | grep -c . || true)"
    n_dangling="$(printf '%s' "$DANGLING" | grep -c . || true)"
    if [ "${n_uncovered:-0}" -gt 0 ] || [ "${n_dangling:-0}" -gt 0 ]; then
        exit 1
    fi
fi
exit 0
