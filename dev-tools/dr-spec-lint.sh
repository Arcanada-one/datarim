#!/usr/bin/env bash
# dr-spec-lint.sh — deterministic spec-traceability graph validator (R1).
#
# Builds and checks the graph
#   wish_id -> D-REQ -> V-AC -> plan-step -> evidence
# over an existing task's PRD / plan / expectations artefacts. Read-only: it
# never mutates any datarim/ file.
#
# Rules (each emits a JSONL finding under its stable rule id):
#   dreq-id-format       D-REQ-NN heading matches the canonical two-digit form
#   dreq-id-unique       no duplicate D-REQ-NN within a document
#   covers-resolves      every Covers reference resolves to a declared D-REQ
#   dreq-orphan          D-REQ referenced by no V-AC (warning)
#   dreq-dangling        Covers points to a non-existent D-REQ
#   vac-covers-present   every V-AC declares a Covers line (L3+, warning)
#   vac-binding-present  every V-AC binds to >=1 plan-step/test/evidence (warning)
#   binding-no-duplicate no duplicate (V-AC, binding) pairs (info)
#   axis-separation      deterministic vs statistical axis not mixed (warning)
#   graph-complete-l3    full wish->D-REQ->V-AC->plan->evidence path on L3+
#
# Usage:
#   dr-spec-lint.sh --task <ID> [--root <path>] [--format json|text]
#                   [--advisory] [--dry-run] [--scope all|git-diff]
#                   [--rules a,b] [--ignore c,d] [--report]
#
# Exit: 0 clean / 1 violations (hard mode) / 2 usage-or-configuration error.
# Contract: documentation/reference/validator-contract.md. Rollout: documentation/explanation/spec-traceability-rollout.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="${SCRIPT_DIR}/../scripts/lib/spec-graph.sh"
RULES_FILE="${SCRIPT_DIR}/dr-spec-rules.yaml"

if [ ! -f "$LIB" ]; then
    echo "ERROR: shared lib not found: $LIB" >&2
    exit 2
fi
# shellcheck source=scripts/lib/spec-graph.sh
. "$LIB"

# ---------------------------------------------------------------------------
# Parse flags (shared vocabulary via the lib; --task is required here).
# ---------------------------------------------------------------------------

parse_common_flags "$@"
# Reject any leftover positional args the lib could not classify.
if [ "${#SPEC_REMAINING_ARGS[@]}" -gt 0 ]; then
    usage_die "unexpected argument: ${SPEC_REMAINING_ARGS[0]}"
fi

[ -n "$SPEC_TASK" ] || usage_die "--task <ID> is required"
if ! printf '%s' "$SPEC_TASK" | grep -qE '^[A-Z]+-[0-9]+(-[A-Za-z0-9]+)*$'; then
    usage_die "invalid --task id: $SPEC_TASK"
fi

load_rules "$RULES_FILE"
effective_ruleset    # honours --rules/--ignore; exits 2 on mis-config

# ---------------------------------------------------------------------------
# Resolve artefacts.
# ---------------------------------------------------------------------------

ROOT="${SPEC_ROOT:-$PWD}"
[ -d "$ROOT" ] || usage_die "root not found: $ROOT"

# Walk up to find datarim/ if not directly present.
DATARIM_ROOT=""
search="$ROOT"
while [ "$search" != "/" ] && [ -n "$search" ]; do
    if [ -d "$search/datarim" ]; then
        DATARIM_ROOT="$search/datarim"
        break
    fi
    search="$(dirname "$search")"
done
[ -n "$DATARIM_ROOT" ] || usage_die "datarim/ not found from $ROOT"

PRD_FILE="$DATARIM_ROOT/prd/PRD-${SPEC_TASK}.md"
PLAN_FILE="$DATARIM_ROOT/plans/${SPEC_TASK}-plan.md"
EXP_FILE="$DATARIM_ROOT/tasks/${SPEC_TASK}-expectations.md"
TASK_FILE="$DATARIM_ROOT/tasks/${SPEC_TASK}-task-description.md"
QA_FILE="$DATARIM_ROOT/qa/qa-report-${SPEC_TASK}.md"
COMPLIANCE_FILE="$DATARIM_ROOT/reports/compliance-report-${SPEC_TASK}.md"

# The graph needs at least one source artefact (PRD or plan) to exist.
if [ ! -f "$PRD_FILE" ] && [ ! -f "$PLAN_FILE" ]; then
    usage_die "no PRD or plan artefact for $SPEC_TASK under $DATARIM_ROOT (prd/ plans/)"
fi

# Spec-graph documents to scan (PRD carries D-REQ + V-AC; plan may carry V-AC).
SPEC_DOCS=()
[ -f "$PRD_FILE" ] && SPEC_DOCS+=("$PRD_FILE")
[ -f "$PLAN_FILE" ] && SPEC_DOCS+=("$PLAN_FILE")

# Determine complexity from the canonical field, with task-description fallback.
LEVEL="L3"
if [ -f "$PRD_FILE" ] && grep -qiE '^[[:space:]]*(\*\*)?complexity[^:]*:[^[:alnum:]]*(Level[[:space:]]+4|L4)\b' "$PRD_FILE"; then LEVEL="L4"
elif [ -f "$PRD_FILE" ] && grep -qiE '^[[:space:]]*(\*\*)?complexity[^:]*:[^[:alnum:]]*(Level[[:space:]]+2|L2)\b' "$PRD_FILE"; then LEVEL="L2"
elif [ -f "$PRD_FILE" ] && grep -qiE '^[[:space:]]*(\*\*)?complexity[^:]*:[^[:alnum:]]*(Level[[:space:]]+1|L1)\b' "$PRD_FILE"; then LEVEL="L1"
elif [ -f "$TASK_FILE" ]; then
    if grep -qiE '^complexity:[[:space:]]*L4' "$TASK_FILE"; then LEVEL="L4"
    elif grep -qiE '^complexity:[[:space:]]*L2' "$TASK_FILE"; then LEVEL="L2"
    elif grep -qiE '^complexity:[[:space:]]*L1' "$TASK_FILE"; then LEVEL="L1"
    fi
fi

# ---------------------------------------------------------------------------
# Findings bookkeeping. We collect findings into a temp file (JSONL) so we can
# both count them and choose the output format at the end.
# ---------------------------------------------------------------------------

FINDINGS_TMP="$(mktemp)"
trap 'rm -f "$FINDINGS_TMP"' EXIT
VIOLATION_COUNT=0

# record <severity> <category> <check_name> <artifact_ref> <ac_csv> <ev_type> <ev_source> <ev_excerpt>
record() {
    # Honour the effective rule set: only emit findings for enabled rules.
    rule_enabled "$3" || return 0
    rule_applies_to_level "$3" "$LEVEL" || return 0
    emit_finding "$@" >> "$FINDINGS_TMP"
    VIOLATION_COUNT=$((VIOLATION_COUNT + 1))
}

# short -- truncate to 120 CHARACTERS (not bytes). cut -c1-120 slices by byte
# under some locales/inputs, which can cut a multibyte codepoint (e.g. Cyrillic)
# in half and produce invalid UTF-8 that later crashes json.loads/UnicodeEncodeError
# downstream (TUNE-0482). python3 is already a hard dependency of this script
# (see emit_finding in spec-graph.sh and the FAIL-text heredoc below), so slicing
# via sys.stdin.read()[:120] is codepoint-safe and adds no new dependency.
short() {
    printf '%s' "$1" | tr -d '\n' | python3 -c 'import sys; sys.stdout.write(sys.stdin.read()[:120])'
}

# ---------------------------------------------------------------------------
# Build the graph from each spec doc.
# ---------------------------------------------------------------------------

# Aggregate declared D-REQ ids (across docs) into a newline list.
ALL_DECLARED=""

for doc in "${SPEC_DOCS[@]}"; do
    base="${doc##*/}"

    # ---- D-REQ declarations: format + uniqueness ----
    declared_in_doc=""
    seen_ids=""
    # Scan every D-REQ declaration. Two canonical PRD forms are accepted:
    #   (a) "#### D-REQ-NN" heading form, and
    #   (b) "- **D-REQ-NN** — ..." bold-list form (the form the /dr-prd template's
    #       Requirements section emits as a bullet list). Recognising both keeps the
    #       Covers/dreq-dangling resolution from false-firing on a well-formed PRD
    #       that declared its D-REQs as a bullet list (DEV-1547, DEV-1552-FU).
    while IFS= read -r hline; do
        [ -n "$hline" ] || continue
        lineno="${hline%%:*}"
        text="${hline#*:}"
        # Is it a well-formed D-REQ id heading?
        if printf '%s' "$text" | grep -qE "$D_REQ_ID_RE"; then
            id="$(printf '%s' "$text" | grep -oE "$D_REQ_REF_RE" | head -1)"
            # uniqueness within the doc
            if printf '%s\n' "$seen_ids" | grep -qx "$id"; then
                record error consistency dreq-id-unique "${base}:${lineno}" "" \
                    file_quote "${base}:${lineno}" "duplicate requirement id $id"
            else
                seen_ids="${seen_ids}${id}"$'\n'
                declared_in_doc="${declared_in_doc}${id}"$'\n'
                ALL_DECLARED="${ALL_DECLARED}${id}"$'\n'
            fi
        else
            # malformed D-REQ-ish heading (e.g. single-digit slug)
            record error correctness dreq-id-format "${base}:${lineno}" "" \
                file_quote "${base}:${lineno}" "$(short "malformed D-REQ heading: $text")"
        fi
    done < <(grep -nE '^#### D-REQ|^[[:space:]]*[-*][[:space:]]+\*\*D-REQ' "$doc" 2>/dev/null)
done

# Build a sorted-unique declared list for resolution checks.
DECLARED_UNIQUE="$(printf '%s' "$ALL_DECLARED" | grep -E "^${D_REQ_REF_RE}$" | sort -u)"

# Track which D-REQ ids are referenced by at least one Covers line.
REFERENCED=""
# Track explicit V-AC -> D-REQ pairs for per-wish path validation.
VAC_REFERENCED=""

# ---- V-AC items + their Covers binding ----
# V-AC items are DECLARED in the PRD (with their Covers line); the plan only
# *references* them as bindings. So the Covers/orphan/axis checks scan the PRD
# (the declaration doc); the plan is consulted for binding presence below.
VAC_DOCS=()
[ -f "$PRD_FILE" ] && VAC_DOCS+=("$PRD_FILE")
[ "${#VAC_DOCS[@]}" -eq 0 ] && VAC_DOCS=("${SPEC_DOCS[@]}")

# We pair each V-AC item with a Covers line found within the next few lines.
for doc in "${VAC_DOCS[@]}"; do
    base="${doc##*/}"

    # Pre-compute the sorted list of V-AC line numbers so each item's Covers
    # window can be clipped before the NEXT V-AC item (otherwise a later item's
    # Covers line would be mis-attributed to an earlier item that has none).
    vac_lines_sorted="$(collect_vac "$doc" | awk -F'\t' '{print $1}' | sort -n)"

    # Each V-AC label with its line number.
    while IFS=$'\t' read -r vac_line vac_label; do
        [ -n "$vac_label" ] || continue

        # Window = from this V-AC line up to 3 lines, but never reaching the
        # next V-AC item's line.
        window_end=$((vac_line + 3))
        next_vac="$(printf '%s\n' "$vac_lines_sorted" | awk -v cur="$vac_line" '$1 > cur {print $1; exit}')"
        if [ -n "$next_vac" ] && [ "$next_vac" -le "$window_end" ]; then
            window_end=$((next_vac - 1))
        fi
        covers_block="$(awk -v s="$vac_line" -v e="$window_end" 'NR>=s && NR<=e' "$doc")"
        covers_line="$(printf '%s\n' "$covers_block" | grep -nE "$COVERS_LINE_RE" | head -1)"

        if [ -z "$covers_line" ]; then
            # vac-covers-present (L3+ only)
            if [ "$LEVEL" = "L3" ] || [ "$LEVEL" = "L4" ]; then
                record warning completeness vac-covers-present "${base}:${vac_line}" "$vac_label" \
                    absent "${base}:${vac_line}" "V-AC $vac_label has no Covers line"
            fi
        else
            # Resolve each referenced D-REQ id.
            refs="$(printf '%s' "$covers_block" | grep -E "$COVERS_LINE_RE" | grep -oE "$D_REQ_REF_RE")"
            while IFS= read -r ref; do
                [ -n "$ref" ] || continue
                REFERENCED="${REFERENCED}${ref}"$'\n'
                VAC_REFERENCED="${VAC_REFERENCED}${vac_label}"$'\t'"${ref}"$'\n'
                if ! printf '%s\n' "$DECLARED_UNIQUE" | grep -qx "$ref"; then
                    record error consistency dreq-dangling "${base}:${vac_line}" "$vac_label" \
                        file_quote "${base}:${vac_line}" "Covers $ref does not resolve to a declared D-REQ"
                    record error consistency covers-resolves "${base}:${vac_line}" "$vac_label" \
                        file_quote "${base}:${vac_line}" "unresolved Covers reference: $ref"
                fi
            done <<< "$refs"
        fi

        # vac-binding-present: plan edges are explicit, never inferred from prose.
        if { [ "$LEVEL" = "L3" ] || [ "$LEVEL" = "L4" ]; } \
            && [ "$SPEC_STAGE" != "prd" ]; then
            if ! collect_verifies "$PLAN_FILE" | awk -F'\t' '{print $2}' | grep -qx "$vac_label"; then
                record warning completeness vac-binding-present "${base}:${vac_line}" "$vac_label" \
                    absent "${base}:${vac_line}" "V-AC $vac_label has no explicit Verifies plan binding"
            fi
        fi
    done < <(collect_vac "$doc")
done

# ---- dreq-orphan: declared D-REQ referenced by no V-AC ----
REFERENCED_UNIQUE="$(printf '%s' "$REFERENCED" | grep -E "^${D_REQ_REF_RE}$" | sort -u)"
if [ -n "$DECLARED_UNIQUE" ]; then
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        if ! printf '%s\n' "$REFERENCED_UNIQUE" | grep -qx "$id"; then
            record warning completeness dreq-orphan "PRD-${SPEC_TASK}.md" "" \
                absent "PRD-${SPEC_TASK}.md" "requirement $id is referenced by no V-AC (orphan)"
        fi
    done <<< "$DECLARED_UNIQUE"
fi

# ---- binding-no-duplicate: duplicate (V-AC, D-REQ) Covers pairs ----
for doc in "${SPEC_DOCS[@]}"; do
    base="${doc##*/}"
    dup="$(collect_covers "$doc" | awk -F'\t' '{print $2}' | sort | uniq -d)"
    if [ -n "$dup" ]; then
        while IFS= read -r d; do
            [ -n "$d" ] || continue
            record info consistency binding-no-duplicate "${base}" "" \
                file_quote "${base}" "duplicate Covers binding for $d"
        done <<< "$dup"
    fi
done

# ---- axis-separation: a V-AC group mixing deterministic + statistical cues ----
for doc in "${SPEC_DOCS[@]}"; do
    base="${doc##*/}"
    while IFS=$'\t' read -r vac_line vac_label; do
        [ -n "$vac_label" ] || continue
        block="$(awk -v s="$vac_line" -v e=$((vac_line + 2)) 'NR>=s && NR<=e' "$doc")"
        has_det=0; has_stat=0
        printf '%s\n' "$block" | grep -qiE '\bexit code\b|\brule match\b|\btype assert|\bshape check\b|\bregex\b' && has_det=1
        printf '%s\n' "$block" | grep -qiE '\brate\b|\bpercentile\b|\bSLA\b|\bp9[0-9]\b|\bthreshold\b|\bdistribution\b|\bsoak\b' && has_stat=1
        if [ "$has_det" -eq 1 ] && [ "$has_stat" -eq 1 ]; then
            record warning consistency axis-separation "${base}:${vac_line}" "$vac_label" \
                file_quote "${base}:${vac_line}" "V-AC $vac_label mixes deterministic and statistical axes"
        fi
    done < <(collect_vac "$doc")
done

# ---- graph-complete-l3: every current wish has a stage-appropriate path ----
if { [ "$LEVEL" = "L3" ] || [ "$LEVEL" = "L4" ]; } && [ -f "$EXP_FILE" ]; then
    VAC_DECLARED="$(collect_vac "$PRD_FILE" | awk -F'\t' '{print $2}' | sort -u)"
    PLAN_BOUND="$(collect_verifies "$PLAN_FILE" | awk -F'\t' '{print $2}' | sort -u)"
    EVIDENCE_BOUND="$(collect_evidence "$TASK_FILE" "$QA_FILE" "$COMPLIANCE_FILE" \
        | awk -F'\t' '{print $2}' | sort -u)"
    # Split the tab-separated record with parameter expansion, NOT
    # `IFS=$'\t' read`: tab is IFS-whitespace, so a `read` collapses an empty
    # middle field and shifts the columns. A wish with a deliberate no-link
    # dash (empty vac) would then read `status` into `vac` and mis-route to the
    # `undeclared` branch with a garbage id. Explicit `%%`/`##` trimming keeps
    # the empty vac empty so it hits the correct `no linked V-AC` branch.
    # Source: TUNE-0473.
    while IFS= read -r _rec; do
        wish="${_rec%%$'\t'*}"; _rest="${_rec#*$'\t'}"
        vac="${_rest%%$'\t'*}"; _rest="${_rest#*$'\t'}"
        status="${_rest%%$'\t'*}"
        valid_operator_override="${_rest##*$'\t'}"
        [ -n "$wish" ] || continue
        case "$status" in deleted|n-a) continue ;; esac
        [ "$valid_operator_override" = "yes" ] && continue
        if [ -z "$vac" ]; then
            record error completeness graph-complete-l3 "${SPEC_TASK}-expectations.md" "" \
                absent "${SPEC_TASK}-expectations.md" "wish $wish has no linked V-AC"
            continue
        fi
        if ! printf '%s\n' "$VAC_DECLARED" | grep -qx "$vac"; then
            record error completeness graph-complete-l3 "${SPEC_TASK}-expectations.md" "$vac" \
                absent "${SPEC_TASK}-expectations.md" "wish $wish links to undeclared $vac"
            continue
        fi
        if ! printf '%s' "$VAC_REFERENCED" | awk -F'\t' -v target="$vac" \
            '$1 == target {found=1} END {exit(found ? 0 : 1)}'; then
            record error completeness graph-complete-l3 "${SPEC_TASK}-expectations.md" "$vac" \
                absent "$PRD_FILE" "wish $wish has no D-REQ coverage through $vac"
            continue
        fi
        case "$SPEC_STAGE" in
            plan|do|qa|compliance|verify|all)
                if ! printf '%s\n' "$PLAN_BOUND" | grep -qx "$vac"; then
                    record error completeness graph-complete-l3 "${SPEC_TASK}-expectations.md" "$vac" \
                        absent "$PLAN_FILE" "wish $wish has no explicit plan binding for $vac"
                    continue
                fi
                ;;
        esac
        case "$SPEC_STAGE" in
            do|qa|compliance|all)
                if ! printf '%s\n' "$EVIDENCE_BOUND" | grep -qx "$vac"; then
                    record error completeness graph-complete-l3 "${SPEC_TASK}-expectations.md" "$vac" \
                        absent "$TASK_FILE" "wish $wish has no explicit evidence for $vac"
                fi
                ;;
        esac
    done < <(collect_expectation_links "$EXP_FILE")
fi

# ---------------------------------------------------------------------------
# Emit + exit.
# ---------------------------------------------------------------------------

# Defensive invariant: VIOLATION_COUNT must equal the JSONL line count.
actual_lines="$(grep -c . "$FINDINGS_TMP" 2>/dev/null)"
actual_lines="${actual_lines:-0}"
if [ "$actual_lines" -ne "$VIOLATION_COUNT" ]; then
    echo "ERROR: internal invariant violated: finding count mismatch ($actual_lines != $VIOLATION_COUNT)" >&2
    exit 2
fi

if [ "$SPEC_DRY_RUN" -eq 1 ]; then
    # Graph built, report nothing.
    echo "[dry-run] graph built for $SPEC_TASK ($LEVEL); ${VIOLATION_COUNT} finding(s) suppressed" >&2
    exit 0
fi

if [ "$SPEC_FORMAT" = "json" ]; then
    cat "$FINDINGS_TMP"
else
    if [ "$VIOLATION_COUNT" -eq 0 ]; then
        echo "PASS: spec graph clean for $SPEC_TASK ($LEVEL)"
    else
        echo "FAIL: $VIOLATION_COUNT spec-graph finding(s) for $SPEC_TASK ($LEVEL)"
        python3 - "$FINDINGS_TMP" <<'PYEOF'
import json, sys
# Defensive: replace any lone surrogate that could still slip through (e.g. a
# pre-existing findings file written before this fix) rather than crash on
# print(). See TUNE-0482.
sys.stdout.reconfigure(errors="replace")
with open(sys.argv[1], encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        f = json.loads(line)
        print("  [%s] %s  %s — %s" % (
            f["severity"], f["check_name"], f["artifact_ref"],
            f["evidence"].get("excerpt", "")))
PYEOF
    fi
fi

if [ "$SPEC_ADVISORY" -eq 1 ]; then
    exit 0
fi

if [ "$VIOLATION_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
