#!/usr/bin/env bash
# check-coworker-canonical-mirror.sh — Type-Signature Mirror Guard linter.
#
# Enforces the coworker Type-Signature Mirror Guard (see
# skills/coworker-context/SKILL.md § Type-Signature Mirror Guard) against a
# coworker draft or a coworker `write` spec that quotes named types,
# signatures, or enum/union variants from a PRD / canonical source.
#
# A delegate LLM invoked through `coworker write` fabricates type signatures
# readily — an invented borrow, an invented collection variant, or a renamed
# field can survive in prose to a late stage before a surgical-edit pass
# catches it. This linter asserts the three guard conditions on a single file:
#
#   (a) Verbatim canonical block — a `<!-- canonical -->` … `<!-- /canonical -->`
#       fenced pair is present and non-empty.
#   (b) Mirror instruction — the body instructs the delegate to mirror the
#       named types exactly (an unambiguous "mirror … exactly" / "do not
#       invent" / "do not rename" directive is present).
#   (c) Identifier coverage — when the caller supplies the expected identifier
#       names, each MUST appear verbatim in the file body (outside the
#       canonical block). Absent identifiers are drift.
#
# The set of identifiers to grep is derived automatically from the canonical
# block (CamelCase type/variant names — the fabrication surface) and may be
# extended by the caller via repeated --identifier flags (for lowercase or
# exotic names the auto-derivation intentionally skips).
#
# It is stack-agnostic and history-agnostic: no repo path, task ID, IP, or
# hostname is hard-coded. The file under test is supplied by the caller.
#
# Usage:
#   ./scripts/check-coworker-canonical-mirror.sh <draft-or-spec.md>
#   ./scripts/check-coworker-canonical-mirror.sh --quiet <file>
#   ./scripts/check-coworker-canonical-mirror.sh --identifier PostHookContext \
#                                                --identifier Payload <file>
#   COWORKER_MIRROR_FILE=<path> ./scripts/check-coworker-canonical-mirror.sh
#
# Environment:
#   COWORKER_MIRROR_FILE   file under test (alternative to positional arg)
#
# Exit codes:
#   0  guard satisfied — canonical block + mirror instruction + full coverage
#   1  guard unmet — missing block, missing instruction, or identifier drift
#   2  error (missing file, usage error)
#
# Read-only. No writes anywhere. Intended to be called:
#   - from a coworker post-generation surgical-edit pass;
#   - from CI / a stage gate as an advisory guard;
#   - manually by an operator before accepting a type-quoting draft.

set -uo pipefail

QUIET=false
TARGET=""
declare -a EXTRA_IDS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --quiet) QUIET=true ;;
        --identifier)
            shift
            [ "$#" -gt 0 ] || { echo "ERROR: --identifier needs an argument." >&2; exit 2; }
            EXTRA_IDS+=("$1")
            ;;
        -h|--help)
            sed -n '2,50p' "$0"
            exit 0
            ;;
        --*)
            echo "ERROR: unknown option: $1" >&2
            exit 2
            ;;
        *) TARGET="$1" ;;
    esac
    shift
done

if [ -z "$TARGET" ]; then
    TARGET="${COWORKER_MIRROR_FILE:-}"
fi
if [ -z "$TARGET" ]; then
    echo "ERROR: file under test required (positional arg or COWORKER_MIRROR_FILE)." >&2
    echo "Usage: $0 [--quiet] [--identifier NAME ...] <draft-or-spec.md>" >&2
    exit 2
fi
if [ ! -f "$TARGET" ]; then
    echo "ERROR: file under test not found: $TARGET" >&2
    exit 2
fi

OPEN='<!-- canonical -->'
CLOSE='<!-- /canonical -->'

$QUIET || {
    echo "Coworker Type-Signature Mirror Guard"
    echo "  file: $TARGET"
    echo ""
}

fail=0

# ---------------------------------------------------------------------------
# (a) Verbatim canonical block — opening and closing markers both present,
#     with at least one non-blank content line between them.
open_line="$(grep -Fn -- "$OPEN" "$TARGET" | head -n1 | cut -d: -f1)"
close_line="$(grep -Fn -- "$CLOSE" "$TARGET" | head -n1 | cut -d: -f1)"

block_body=""
if [ -n "$open_line" ] && [ -n "$close_line" ] && [ "$close_line" -gt "$open_line" ]; then
    start=$((open_line + 1))
    end=$((close_line - 1))
    if [ "$end" -ge "$start" ]; then
        block_body="$(sed -n "${start},${end}p" "$TARGET" | grep -v '^[[:space:]]*$' || true)"
    fi
fi

if [ -n "$block_body" ]; then
    $QUIET || echo "  [ok]      canonical block present and non-empty"
else
    fail=1
    $QUIET || echo "  [MISSING] <!-- canonical --> … <!-- /canonical --> block (non-empty)"
fi

# ---------------------------------------------------------------------------
# (b) Mirror instruction — a directive telling the delegate to mirror exactly
#     and not invent/rename. Case-insensitive, must co-occur on the intent.
if grep -Eiq 'mirror .*exact' "$TARGET" \
   && grep -Eiq 'do not (invent|rename|paraphrase)' "$TARGET"; then
    $QUIET || echo "  [ok]      mirror instruction present"
else
    fail=1
    $QUIET || echo "  [MISSING] mirror instruction (\"mirror … exactly\" + \"do not invent/rename/paraphrase\")"
fi

# ---------------------------------------------------------------------------
# (c) Identifier coverage — every expected identifier appears verbatim in the
#     body outside the canonical block. Auto-derived identifiers are the type /
#     variant fabrication surface: CamelCase tokens (initial uppercase, ≥3
#     chars) from the canonical block. Lowercase keywords (fn, enum, struct)
#     and parameter/field bindings are not auto-derived — the caller adds any
#     lowercase or exotic name to grep explicitly via --identifier.
derived_ids=""
if [ -n "$block_body" ]; then
    derived_ids="$(printf '%s\n' "$block_body" \
        | grep -oE '[A-Z][A-Za-z0-9_]{2,}' \
        | sort -u || true)"
fi

# Body outside the canonical block (so a name inside the block does not
# self-satisfy coverage).
if [ -n "$open_line" ] && [ -n "$close_line" ]; then
    body_outside="$(awk -v o="$open_line" -v c="$close_line" \
        'NR < o || NR > c' "$TARGET")"
else
    body_outside="$(cat "$TARGET")"
fi

all_ids="$(printf '%s\n' $derived_ids "${EXTRA_IDS[@]:-}" | grep -v '^[[:space:]]*$' | sort -u || true)"

missing_ids=""
if [ -n "$all_ids" ]; then
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        if printf '%s' "$body_outside" | grep -Fq -- "$id"; then
            $QUIET || echo "  [ok]      identifier mirrored: $id"
        else
            fail=1
            missing_ids="$missing_ids $id"
            $QUIET || echo "  [DRIFT]   identifier not mirrored in body: $id"
        fi
    done <<< "$all_ids"
fi

$QUIET || echo ""

if [ "$fail" -ne 0 ]; then
    echo "GUARD UNMET: coworker type-signature mirror guard failed for: $TARGET" >&2
    [ -n "$missing_ids" ] && echo "  identifiers not mirrored in body:$missing_ids" >&2
    echo "  Embed a verbatim <!-- canonical --> block, instruct the delegate to" >&2
    echo "  mirror named types/variants exactly, and grep every expected name" >&2
    echo "  before accepting the draft (see skills/coworker-context/SKILL.md" >&2
    echo "  § Type-Signature Mirror Guard)." >&2
    exit 1
fi

$QUIET || echo "GUARD SATISFIED: canonical block + mirror instruction + full identifier coverage."
exit 0
