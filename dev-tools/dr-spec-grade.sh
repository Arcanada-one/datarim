#!/usr/bin/env bash
# dr-spec-grade.sh — COMPUTED spec-quality grade projection (R10).
#
# Contract (operator amendment, verbatim intent): the grade is a *computed
# projection from findings/verdict*. It READS findings (from --findings <file>,
# stdin, or by running dr-spec-lint for --task), derives a letter from a fixed
# deterministic mapping, and prints it. It is:
#   - never hand-edited,
#   - never persisted as a source of truth (read-only — writes nothing),
#   - never a routing input (emits no BLOCKED / PASS / CONDITIONAL / CTA token),
#   - invoked by no gate.
# It is a dashboard projection only. Same input always yields the same grade.
#
# Deterministic mapping (clean-room native — the letter `E` is intentionally
# absent, a deliberate Datarim choice, not a copy of any external scheme):
#   errors == 0 and warnings == 0          -> A
#   errors == 0 and warnings in 1..3       -> B
#   errors == 0 and warnings >= 4          -> C
#   errors in 1..2                         -> D
#   errors >= 3                            -> F
#
# Usage:
#   dr-spec-grade.sh --findings <file.jsonl>           # from a findings file
#   dr-spec-lint.sh ... --format json | dr-spec-grade.sh   # from stdin
#   dr-spec-grade.sh --task <ID> [--root <path>]       # run lint, then grade
#   [--format json|text]
#
# Exit: 0 always on a successful computation; 2 = usage/configuration error.
# The grade is NOT a verdict — exit code never encodes pass/fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_LINT="${SCRIPT_DIR}/dr-spec-lint.sh"

FINDINGS_FILE=""
TASK=""
ROOT=""
FMT="text"

usage_die() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --findings) shift; [ $# -gt 0 ] || usage_die "--findings requires a path"; FINDINGS_FILE="$1"; shift ;;
        --task)     shift; [ $# -gt 0 ] || usage_die "--task requires an id"; TASK="$1"; shift ;;
        --root)     shift; [ $# -gt 0 ] || usage_die "--root requires a path"; ROOT="$1"; shift ;;
        --format)   shift; [ $# -gt 0 ] || usage_die "--format requires a value"
                    case "$1" in json|text) FMT="$1" ;; *) usage_die "invalid --format: $1" ;; esac; shift ;;
        --help|-h)  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          usage_die "unknown flag: $1" ;;
    esac
done

# ---------------------------------------------------------------------------
# Acquire the findings JSONL (read-only) from exactly one source.
# ---------------------------------------------------------------------------

COMPUTED_FROM=""
FINDINGS_JSON=""

if [ -n "$FINDINGS_FILE" ]; then
    [ -f "$FINDINGS_FILE" ] || usage_die "findings file not found: $FINDINGS_FILE"
    FINDINGS_JSON="$(cat "$FINDINGS_FILE")"
    COMPUTED_FROM="file:${FINDINGS_FILE##*/}"
elif [ -n "$TASK" ]; then
    [ -f "$SPEC_LINT" ] || usage_die "dr-spec-lint.sh not found: $SPEC_LINT"
    lint_args=(--task "$TASK" --format json --advisory)
    [ -n "$ROOT" ] && lint_args+=(--root "$ROOT")
    FINDINGS_JSON="$(bash "$SPEC_LINT" "${lint_args[@]}" 2>/dev/null || true)"
    COMPUTED_FROM="dr-spec-lint:${TASK}"
elif [ ! -t 0 ]; then
    FINDINGS_JSON="$(cat)"
    COMPUTED_FROM="stdin"
else
    usage_die "no findings source: pass --findings <file>, --task <ID>, or pipe JSONL on stdin"
fi

# ---------------------------------------------------------------------------
# Count severities + compute the grade. Pure read; no writes anywhere.
# ---------------------------------------------------------------------------

read -r ERRORS WARNINGS INFOS <<EOF
$(printf '%s\n' "$FINDINGS_JSON" | python3 -c '
import json, sys
e = w = i = 0
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        f = json.loads(line)
    except ValueError:
        continue
    sev = f.get("severity", "")
    if sev == "error":   e += 1
    elif sev == "warning": w += 1
    elif sev == "info":    i += 1
print(e, w, i)
')
EOF

ERRORS="${ERRORS:-0}"; WARNINGS="${WARNINGS:-0}"; INFOS="${INFOS:-0}"

if [ "$ERRORS" -ge 3 ]; then
    GRADE="F"
elif [ "$ERRORS" -ge 1 ]; then
    GRADE="D"
elif [ "$WARNINGS" -ge 4 ]; then
    GRADE="C"
elif [ "$WARNINGS" -ge 1 ]; then
    GRADE="B"
else
    GRADE="A"
fi

# ---------------------------------------------------------------------------
# Emit. No routing token, ever.
# ---------------------------------------------------------------------------

if [ "$FMT" = "json" ]; then
    python3 - "$GRADE" "$ERRORS" "$WARNINGS" "$INFOS" "$COMPUTED_FROM" <<'PYEOF'
import json, sys
grade, e, w, i, src = sys.argv[1:6]
print(json.dumps({
    "grade": grade,
    "basis": {"errors": int(e), "warnings": int(w), "infos": int(i)},
    "computed_from": src,
}))
PYEOF
else
    printf 'spec-grade: %s  (errors=%s warnings=%s infos=%s; computed_from=%s)\n' \
        "$GRADE" "$ERRORS" "$WARNINGS" "$INFOS" "$COMPUTED_FROM"
fi

exit 0
