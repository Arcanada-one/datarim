#!/usr/bin/env bash
# dr-verify-floor.sh — Layer 1 deterministic floor for /dr-verify.
#
# Pre-LLM shell pipeline. Emits JSONL findings to stdout, one record per check
# violation, with `source_layer: "floor"`. Industry pattern (deterministic-tools-
# first, then LLM): Aider --auto-lint/--auto-test, Cursor build-verify.
#
# Inputs:
#   --task <ID>        Mandatory. Task identifier (regex ^[A-Z]+-[0-9]+$).
#   --stage <stage>    prd|plan|do|all. Default: all.
#   --workspace <path> Workspace root. Default: $PWD. Walks up to find datarim/.
#
# Output (stdout): JSONL findings. Schema fields:
#   finding_id, source_layer, artifact_ref, ac_criteria, severity,
#   category, evidence{type,source,excerpt}, check_name
#
# Stderr: progress lines per check (`[check_name] ...`).
#
# Exit code:
#   0   no high-severity findings (floor clean — proceed to Layer 2/3)
#   1-N count of high-severity findings (capped at 250)
#   2   invocation error (bad args, missing datarim/)
#
# See: skills/self-verification.md § Layer 1.

# strict-mode rationale: -e omitted intentionally (not sloppy). emit_finding calls python3 as its
# last statement in the function; under -e a single encoding error would abort the entire findings
# loop, silencing all subsequent findings. Explicit guards (|| true on shellcheck call, if/[ checks,
# return 0 paths) handle all non-zero exits. Aggregator contract: exit = count of high-severity
# findings, not first sub-command error. -u and pipefail are kept; only -e is dropped.
set -uo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

TASK_ID=""
STAGE="all"
WORKSPACE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --task)
            shift
            [ $# -gt 0 ] || { echo "dr-verify-floor: --task requires value" >&2; exit 2; }
            TASK_ID="$1"; shift ;;
        --stage)
            shift
            [ $# -gt 0 ] || { echo "dr-verify-floor: --stage requires value" >&2; exit 2; }
            STAGE="$1"; shift ;;
        --workspace)
            shift
            [ $# -gt 0 ] || { echo "dr-verify-floor: --workspace requires value" >&2; exit 2; }
            WORKSPACE="$1"; shift ;;
        --help|-h)
            sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "dr-verify-floor: unknown arg: $1" >&2
            exit 2 ;;
    esac
done

if [ -z "$TASK_ID" ]; then
    echo "dr-verify-floor: --task <TASK-ID> required" >&2
    exit 2
fi
if ! printf '%s' "$TASK_ID" | grep -qE '^[A-Z]+-[0-9]+$'; then
    echo "dr-verify-floor: invalid task-id (regex ^[A-Z]+-[0-9]+\$): $TASK_ID" >&2
    exit 2
fi
case "$STAGE" in
    prd|plan|do|all) ;;
    *) echo "dr-verify-floor: invalid --stage (prd|plan|do|all): $STAGE" >&2; exit 2 ;;
esac

if [ -z "$WORKSPACE" ]; then
    WORKSPACE="$PWD"
fi
if [ ! -d "$WORKSPACE" ]; then
    echo "dr-verify-floor: workspace not found: $WORKSPACE" >&2
    exit 2
fi

# Walk up to find datarim/
DATARIM_ROOT=""
search_dir="$WORKSPACE"
while [ "$search_dir" != "/" ] && [ -n "$search_dir" ]; do
    if [ -d "$search_dir/datarim" ]; then
        DATARIM_ROOT="$search_dir/datarim"
        break
    fi
    search_dir="$(dirname "$search_dir")"
done

if [ -z "$DATARIM_ROOT" ]; then
    echo "dr-verify-floor: datarim/ not found walking up from $WORKSPACE" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Finding emission helper. Single python call per finding for robust JSON quoting.
# ---------------------------------------------------------------------------

FINDING_COUNTER=0
HIGH_SEVERITY_COUNT=0

emit_finding() {
    # Args: severity category check_name artifact_ref ac_csv ev_type ev_source ev_excerpt
    local severity="$1"
    local category="$2"
    local check_name="$3"
    local artifact_ref="$4"
    local ac_csv="$5"
    local ev_type="$6"
    local ev_source="$7"
    local ev_excerpt="$8"

    FINDING_COUNTER=$((FINDING_COUNTER + 1))
    if [ "$severity" = "high" ]; then
        HIGH_SEVERITY_COUNT=$((HIGH_SEVERITY_COUNT + 1))
    fi

    python3 - "$severity" "$category" "$check_name" "$artifact_ref" \
              "$ac_csv" "$ev_type" "$ev_source" "$ev_excerpt" \
              "$FINDING_COUNTER" <<'PYEOF'
import json, sys
sev, cat, chk, art, ac_csv, ev_t, ev_s, ev_e, idx = sys.argv[1:10]
ac_list = [a for a in ac_csv.split(',') if a]
finding = {
    "finding_id": "F-floor-" + str(idx),
    "source_layer": "floor",
    "artifact_ref": art,
    "ac_criteria": ac_list,
    "severity": sev,
    "category": cat,
    "evidence": {
        "type": ev_t,
        "source": ev_s,
        "excerpt": ev_e[:200],
    },
    "check_name": chk,
}
sys.stdout.write(json.dumps(finding, ensure_ascii=False) + "\n")
PYEOF
}

# ---------------------------------------------------------------------------
# Sub-check: AC coverage grep — every AC/TV in PRD must have a verification cue
# (Verify:, backtick command, grep/test/bash/jq nearby).
# ---------------------------------------------------------------------------

check_ac_coverage() {
    local prd_file="$DATARIM_ROOT/prd/PRD-${TASK_ID}.md"
    if [ ! -f "$prd_file" ]; then
        echo "[ac_coverage_grep] SKIP: $prd_file not found" >&2
        return 0
    fi
    echo "[ac_coverage_grep] scanning $prd_file" >&2

    # Extract AC labels (AC-N or TV-N)
    local ac_labels
    ac_labels="$(grep -oE '\b(AC|TV)-[0-9]+\b' "$prd_file" | sort -u)"
    if [ -z "$ac_labels" ]; then
        echo "[ac_coverage_grep] no AC/TV labels found" >&2
        return 0
    fi

    local ac_count=0
    local ac
    while IFS= read -r ac; do
        [ -n "$ac" ] || continue
        ac_count=$((ac_count + 1))

        # Get the first line that defines this AC
        local def_line
        def_line="$(grep -nE -- "(\\*\\*${ac}|^${ac}:|^- \\*\\*${ac}|- ${ac}:)" "$prd_file" | head -1)"
        [ -n "$def_line" ] || continue

        local lineno
        lineno="${def_line%%:*}"

        # Look at definition line + next 5 lines for verification cue
        local block
        block="$(awk -v start="$lineno" -v end=$((lineno + 5)) 'NR>=start && NR<=end' "$prd_file")"

        if printf '%s' "$block" | grep -qE 'Verify:|\bgrep\b|\btest\b|\bbash\b|\bjq\b|\bawk\b|\bpython3?\b|\bcurl\b|`[A-Za-z0-9._/-]+'; then
            continue
        fi

        local first_line
        first_line="$(printf '%s' "$block" | head -1 | tr -d '\n' | cut -c1-180)"
        emit_finding "medium" "completeness" "ac_coverage_grep" \
                     "${prd_file##*/}:${lineno}" "$ac" \
                     "file_quote" "$prd_file:$lineno" "$first_line"
    done <<< "$ac_labels"

    echo "[ac_coverage_grep] checked $ac_count AC/TV labels" >&2
}

# ---------------------------------------------------------------------------
# Sub-check: file-touched audit — files referenced in plan tables must resolve.
# Backticked paths with known extensions are heuristically extracted.
# ---------------------------------------------------------------------------

check_file_touched() {
    local plan_file="$DATARIM_ROOT/plans/${TASK_ID}-plan.md"
    if [ ! -f "$plan_file" ]; then
        echo "[file_touched_audit] SKIP: $plan_file not found" >&2
        return 0
    fi
    echo "[file_touched_audit] scanning $plan_file" >&2

    local file_refs
    # shellcheck disable=SC2016 # literal backticks are part of the markdown code-span pattern, not a shell expansion
    file_refs="$(grep -oE '`[A-Za-z0-9._/-]+\.(sh|md|php|yml|yaml|json|py|ts|js|tsx|jsx)`' "$plan_file" \
                 | tr -d '`' | sort -u)"

    if [ -z "$file_refs" ]; then
        echo "[file_touched_audit] no file refs detected" >&2
        return 0
    fi

    local checked=0 missing=0
    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        checked=$((checked + 1))

        local resolved=""
        if [ "${f#/}" != "$f" ]; then
            resolved="$f"
        elif [ -e "$WORKSPACE/$f" ]; then
            resolved="$WORKSPACE/$f"
        elif [ -e "$(dirname "$DATARIM_ROOT")/$f" ]; then
            resolved="$(dirname "$DATARIM_ROOT")/$f"
        fi

        if [ -z "$resolved" ] || [ ! -e "$resolved" ]; then
            missing=$((missing + 1))
            emit_finding "low" "completeness" "file_touched_audit" \
                         "${plan_file##*/}" "" \
                         "file_quote" "$f" \
                         "referenced in plan but not resolvable in workspace (NEW pre-/dr-do or phantom)"
        fi
    done <<< "$file_refs"

    echo "[file_touched_audit] checked=$checked missing=$missing" >&2
}

# ---------------------------------------------------------------------------
# Sub-check: test-presence parse — heuristic manifest detection (informational).
# ---------------------------------------------------------------------------

check_test_presence() {
    local manifests=()
    local m
    for m in package.json pyproject.toml Cargo.toml go.mod composer.json Gemfile; do
        if [ -f "$WORKSPACE/$m" ]; then
            manifests+=("$m")
        fi
    done

    if [ ${#manifests[@]} -eq 0 ]; then
        echo "[test_presence_parse] SKIP: no manifest detected at $WORKSPACE" >&2
        return 0
    fi

    echo "[test_presence_parse] manifests: ${manifests[*]}" >&2
}

# ---------------------------------------------------------------------------
# Sub-check: shellcheck on dev-tools/ + scripts/ — emits per-warning findings.
# ---------------------------------------------------------------------------

check_shellcheck() {
    if ! command -v shellcheck >/dev/null 2>&1; then
        echo "[shellcheck] SKIP: shellcheck not installed" >&2
        return 0
    fi

    local roots=()
    local r
    for r in dev-tools scripts; do
        [ -d "$WORKSPACE/$r" ] && roots+=("$WORKSPACE/$r")
    done

    if [ ${#roots[@]} -eq 0 ]; then
        echo "[shellcheck] SKIP: no dev-tools/ or scripts/ in $WORKSPACE" >&2
        return 0
    fi

    local scripts=()
    local s
    while IFS= read -r s; do
        [ -n "$s" ] && scripts+=("$s")
    done < <(find "${roots[@]}" -name '*.sh' -type f 2>/dev/null | sort)

    if [ ${#scripts[@]} -eq 0 ]; then
        echo "[shellcheck] SKIP: no .sh files under ${roots[*]}" >&2
        return 0
    fi

    echo "[shellcheck] scanning ${#scripts[@]} scripts" >&2
    local hits=0
    for s in "${scripts[@]}"; do
        local out
        out="$(shellcheck -S warning -f gcc "$s" 2>&1 || true)"
        [ -z "$out" ] && continue
        local line
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            local sev="low"
            case "$line" in
                *': error:'*)   sev="high" ;;
                *': warning:'*) sev="medium" ;;
            esac
            hits=$((hits + 1))
            emit_finding "$sev" "safety" "shellcheck" \
                         "${s#"$WORKSPACE/"}" "" \
                         "test_output" "shellcheck $s" \
                         "${line:0:200}"
        done <<< "$out"
    done

    echo "[shellcheck] hits=$hits" >&2
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

case "$STAGE" in
    prd)  check_ac_coverage ;;
    plan) check_ac_coverage; check_file_touched ;;
    do)   check_file_touched; check_test_presence; check_shellcheck ;;
    all)  check_ac_coverage; check_file_touched; check_test_presence; check_shellcheck ;;
esac

# Warn if zero findings were emitted AND shellcheck produced no hits (all checks were SKIP).
# This prevents a silent all-SKIP run from appearing as a clean pass to the operator.
# Typical cause: script invoked from a directory whose walk-up finds a datarim/ that does not
# contain PRD/plan files for the target task (e.g. Projects/Datarim/ instead of workspace root).
if [ "$FINDING_COUNTER" -eq 0 ]; then
    echo "[WARN] dr-verify-floor: all checks SKIPped or produced 0 findings." >&2
    echo "[WARN] Ensure --workspace points to the workspace root containing datarim/prd/PRD-${TASK_ID}.md." >&2
    echo "[WARN] DATARIM_ROOT resolved to: $DATARIM_ROOT" >&2
fi

echo "[summary] findings=$FINDING_COUNTER high_severity=$HIGH_SEVERITY_COUNT" >&2

# Cap exit code at 250 to stay within bash 0..255 range and avoid 251..255 reserved bands.
if [ "$HIGH_SEVERITY_COUNT" -gt 250 ]; then
    exit 250
fi
exit "$HIGH_SEVERITY_COUNT"
