#!/usr/bin/env bash
# check-known-fix-persistence.sh — assert that a task RECORDED a known-fix decision.
#
# `/dr-archive` Step 0.6 and the reflecting skill's known-fix writer define two
# legitimate outcomes for every completed task:
#
#   1. a verified reusable fix  -> exactly one ```json known_fix block in
#      datarim/insights/INSIGHTS-<ID>.md, schema-valid per known-fix-memory.py
#   2. no verified reusable fix -> an explicit "none" verdict in the reflection
#
# Before this gate there was no way to tell those apart from a third state:
# the step never ran and nothing was written. All three looked identical on
# disk — absence. That is why the mechanism could be fully deployed and produce
# zero records for months without any signal. This script makes the silent
# state observable, which is the whole point: it does not judge whether a fix
# SHOULD have been found, only that a decision was actually recorded.
#
# Verdicts (exit code is the contract):
#   exit 0 = recorded  — a schema-valid known_fix block exists for the task
#   exit 0 = declined  — the reflection explicitly records "none"
#   exit 1 = silent    — neither; no decision was recorded (the defect state)
#   exit 2 = usage or integrity error (bad args, unreadable root, broken helper)
#
# `silent` is exit 1 rather than exit 0 so a caller can gate on it. The
# remediation is one line in the reflection, never an invented record: a task
# that genuinely produced no reusable fix declares that, and passes.
#
# Usage:
#   check-known-fix-persistence.sh --task <ID> --root <repo-root>
#   check-known-fix-persistence.sh --task <ID> --root <root> --quiet

set -euo pipefail

TASK=""
ROOT=""
QUIET=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --task) TASK="${2:-}"; shift 2 ;;
        --task=*) TASK="${1#--task=}"; shift ;;
        --root) ROOT="${2:-}"; shift 2 ;;
        --root=*) ROOT="${1#--root=}"; shift ;;
        --quiet) QUIET=1; shift ;;
        -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
        *) echo "ERROR: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

say() {
    [ "$QUIET" -eq 1 ] || echo "$1"
}

if [ -z "$TASK" ] || [ -z "$ROOT" ]; then
    echo "ERROR: --task and --root are required" >&2
    exit 2
fi

# Validate the task id shape before it reaches a path (untrusted input).
case "$TASK" in
    [A-Z][A-Z0-9]*-[0-9][0-9][0-9][0-9]*) : ;;
    *) echo "ERROR: invalid task id '$TASK'" >&2; exit 2 ;;
esac

if [ ! -d "$ROOT" ]; then
    echo "ERROR: root is not a directory: $ROOT" >&2
    exit 2
fi

INSIGHT="$ROOT/datarim/insights/INSIGHTS-$TASK.md"
REFLECTION="$ROOT/datarim/reflection/reflection-$TASK.md"
VALIDATOR="$(dirname "$0")/known-fix-memory.py"

# --- verdict 1: a recorded, schema-valid known_fix ---------------------------
#
# Delegate the schema decision to known-fix-memory.py rather than re-implement
# it here; two validators would drift and the strict one would stop being the
# one enforced.
if [ -f "$INSIGHT" ] && grep -qF '```json known_fix' "$INSIGHT"; then
    if [ ! -f "$VALIDATOR" ]; then
        echo "ERROR: validator not found: $VALIDATOR" >&2
        exit 2
    fi
    if python3 "$VALIDATOR" validate --root "$ROOT" --task "$TASK" >/dev/null 2>&1; then
        say "recorded: schema-valid known_fix in datarim/insights/INSIGHTS-$TASK.md"
        exit 0
    fi
    # A block that is present but invalid is NOT a silent step — the decision
    # was made and the record is broken. Report it as its own failure so the
    # remediation ("repair the record") is not confused with ("write a verdict").
    echo "invalid: known_fix block present but rejected by known-fix-memory.py" >&2
    python3 "$VALIDATOR" validate --root "$ROOT" --task "$TASK" >/dev/null || true
    exit 1
fi

# --- verdict 2: an explicit declination --------------------------------------
#
# Accept both the inline prose form ("Known Fix: none") mandated by the
# reflecting skill and the template's "## Known Fix" section whose body opens
# with "none". Matching is case-insensitive and tolerates Markdown emphasis so
# a reflection is not failed over bolding.
if [ -f "$REFLECTION" ]; then
    # Strip Markdown emphasis once, up front. "**Known Fix:** None." and
    # "Known Fix: none" are the same verdict, and a reflection must never fail
    # this gate over bolding.
    PLAIN="$(tr -d '*_`' <"$REFLECTION")"

    # A verdict is just as valid as a list item ("- Known Fix: none.") as it is
    # as a standalone line; a real reflection in the corpus used exactly that
    # form and an earlier revision of this gate scored it silent.
    if printf '%s\n' "$PLAIN" \
        | grep -qiE '^[[:space:]]*([-+*]|[0-9]+[.)])?[[:space:]]*known fix[[:space:]]*:[[:space:]]*none'; then
        say "declined: reflection records an explicit 'none' verdict"
        exit 0
    fi

    # Section form: a "## Known Fix" heading whose first non-blank body line
    # opens with "none".
    if printf '%s\n' "$PLAIN" | awk '
        { line = tolower($0) }
        line ~ /^#{2,6}[[:space:]]+known fix[[:space:]]*$/ { inside = 1; next }
        inside && line ~ /^#{1,6}[[:space:]]/ { inside = 0 }
        inside && NF {
            sub(/^[[:space:]]+/, "", line)
            sub(/^([-+*]|[0-9]+[.)])[[:space:]]+/, "", line)
            if (line ~ /^none/) { found = 1 }
            inside = 0
        }
        END { exit(found ? 0 : 1) }
    '; then
        say "declined: reflection's Known Fix section records 'none'"
        exit 0
    fi
fi

# --- verdict 3: silent -------------------------------------------------------
if [ ! -f "$REFLECTION" ]; then
    echo "silent: no reflection at datarim/reflection/reflection-$TASK.md and no known_fix record" >&2
else
    echo "silent: no known_fix record and no explicit 'none' verdict in reflection-$TASK.md" >&2
fi
echo "remediation: record the decision — a validated known_fix block, or 'Known Fix: none'" >&2
exit 1
