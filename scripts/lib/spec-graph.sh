# shellcheck shell=bash
# shellcheck disable=SC2034  # several constants/arrays are populated here and read by the sourcing validators; shellcheck cannot see those consumers.
#
# spec-graph.sh — shared library for the Datarim spec-traceability layer.
#
# Sourced (never executed) by the four validators:
#   dev-tools/dr-spec-lint.sh   — graph validator (R1)
#   dev-tools/dr-trace.sh       — coverage report (R5)
#   dev-tools/dr-lint.sh        — umbrella + registry façade (R4)
#   dev-tools/dr-spec-grade.sh  — computed grade projection (R10)
#
# This file is the ONE place the common validator contract (R7) lives:
#   - emit_finding()       : JSONL finding record (schema mirrors dr-verify-floor.sh)
#   - usage_die()          : print message + exit 2 (usage/configuration error)
#   - parse_common_flags() : --format json|text, --root, --report, --task,
#                            --dry-run, --advisory, --scope, --report-file
#   - load_rules()         : parse dr-spec-rules.yaml into the SPEC_RULE_* arrays
#   - effective_ruleset()  : apply --rules / --ignore with mandatory-rule guard
#   - is_mandatory(), rule_severity()
#   - graph helpers: collect_d_req(), collect_covers(), collect_vac()
#
# Exit-code contract (R7), inherited by every validator that sources this lib:
#   0 = valid / clean
#   1 = violations found (hard mode)
#   2 = usage or configuration error (NEVER reported as "0 violations")
#
# Reuse note: emit_finding mirrors dev-tools/dr-verify-floor.sh's python-heredoc
# JSON pattern so /dr-verify floor integration (R6) can re-emit our findings with
# trivial field remapping. set -uo pipefail (NOT -e) per the floor's rationale —
# a single bad finding must never silence the rest of the loop.

# ---------------------------------------------------------------------------
# Resolve and source the schema-regex single-source-of-truth.
# ---------------------------------------------------------------------------

if [ -z "${_SPEC_GRAPH_LIB_DIR:-}" ]; then
    _SPEC_GRAPH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
# shellcheck source=scripts/lib/schema-regex.sh
. "${_SPEC_GRAPH_LIB_DIR}/schema-regex.sh"

# ---------------------------------------------------------------------------
# Common-flag state (defaults). Validators read these after parse_common_flags.
# ---------------------------------------------------------------------------

SPEC_FORMAT="text"        # text | json
SPEC_ROOT=""              # workspace / datarim root override
SPEC_TASK=""              # task id (regex ^[A-Z]+-[0-9]+...)
SPEC_REPORT=0             # human report toggle
SPEC_REPORT_FILE=""       # optional report sink
SPEC_DRY_RUN=0            # build graph, report nothing, exit 0
SPEC_ADVISORY=0           # findings emitted, always exit 0
SPEC_SCOPE="all"          # all | git-diff
SPEC_STAGE="all"          # prd | plan | do | qa | compliance | verify | all
SPEC_RULES_INCLUDE=""     # comma list for --rules
SPEC_RULES_IGNORE=""      # comma list for --ignore
SPEC_REMAINING_ARGS=()    # args the caller still needs to handle

# ---------------------------------------------------------------------------
# usage_die — print message to stderr and exit 2 (usage/configuration error).
# ---------------------------------------------------------------------------

usage_die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 2
}

# ---------------------------------------------------------------------------
# parse_common_flags — consume the shared flag vocabulary. Unknown / malformed
# flags are a usage error (exit 2). Caller-specific flags are collected into
# SPEC_REMAINING_ARGS for the caller to dispatch.
# ---------------------------------------------------------------------------

parse_common_flags() {
    SPEC_REMAINING_ARGS=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --format)
                shift
                [ $# -gt 0 ] || usage_die "--format requires a value (json|text)"
                case "$1" in
                    json|text) SPEC_FORMAT="$1" ;;
                    *) usage_die "invalid --format value: $1 (json|text)" ;;
                esac
                shift ;;
            --root)
                shift
                [ $# -gt 0 ] || usage_die "--root requires a path"
                SPEC_ROOT="$1"; shift ;;
            --task)
                shift
                [ $# -gt 0 ] || usage_die "--task requires a task id"
                SPEC_TASK="$1"; shift ;;
            --report)
                SPEC_REPORT=1; shift ;;
            --report-file)
                shift
                [ $# -gt 0 ] || usage_die "--report-file requires a path"
                SPEC_REPORT_FILE="$1"; shift ;;
            --dry-run)
                SPEC_DRY_RUN=1; shift ;;
            --advisory)
                SPEC_ADVISORY=1; shift ;;
            --scope)
                shift
                [ $# -gt 0 ] || usage_die "--scope requires a value (all|git-diff)"
                case "$1" in
                    all|git-diff) SPEC_SCOPE="$1" ;;
                    *) usage_die "invalid --scope value: $1 (all|git-diff)" ;;
                esac
                shift ;;
            --stage)
                shift
                [ $# -gt 0 ] || usage_die "--stage requires a value"
                case "$1" in
                    prd|plan|do|qa|compliance|verify|all) SPEC_STAGE="$1" ;;
                    *) usage_die "invalid --stage value: $1" ;;
                esac
                shift ;;
            --rules)
                shift
                [ $# -gt 0 ] || usage_die "--rules requires a comma-separated list"
                SPEC_RULES_INCLUDE="$1"; shift ;;
            --ignore)
                shift
                [ $# -gt 0 ] || usage_die "--ignore requires a comma-separated list"
                SPEC_RULES_IGNORE="$1"; shift ;;
            --)
                shift
                while [ $# -gt 0 ]; do SPEC_REMAINING_ARGS+=("$1"); shift; done
                break ;;
            --*)
                usage_die "unknown flag: $1" ;;
            *)
                SPEC_REMAINING_ARGS+=("$1"); shift ;;
        esac
    done
    return 0
}

# ---------------------------------------------------------------------------
# emit_finding — one JSONL record per finding. Schema mirrors dr-verify-floor.sh.
#   args: severity category check_name artifact_ref ac_csv ev_type ev_source ev_excerpt
# source_layer is fixed to "spec-lint" so /dr-verify floor can remap it.
# ---------------------------------------------------------------------------

_SPEC_FINDING_COUNTER=0

emit_finding() {
    local severity="$1" category="$2" check_name="$3" artifact_ref="$4"
    local ac_csv="$5" ev_type="$6" ev_source="$7" ev_excerpt="$8"

    _SPEC_FINDING_COUNTER=$((_SPEC_FINDING_COUNTER + 1))

    python3 - "$severity" "$category" "$check_name" "$artifact_ref" \
              "$ac_csv" "$ev_type" "$ev_source" "$ev_excerpt" \
              "$_SPEC_FINDING_COUNTER" <<'PYEOF'
import json, sys
sev, cat, chk, art, ac_csv, ev_t, ev_s, ev_e, idx = sys.argv[1:10]
ac_list = [a for a in ac_csv.split(',') if a]
finding = {
    "finding_id": "F-spec-" + str(idx),
    "source_layer": "spec-lint",
    "artifact_ref": art,
    "ac_criteria": ac_list,
    "severity": sev,
    "category": cat,
    "evidence": {"type": ev_t, "source": ev_s, "excerpt": ev_e[:200]},
    "check_name": chk,
}
sys.stdout.write(json.dumps(finding, ensure_ascii=False) + "\n")
PYEOF
}

# ---------------------------------------------------------------------------
# Registry loader. Parses the flat dr-spec-rules.yaml into PARALLEL INDEXED
# arrays (NOT associative arrays — the framework targets macOS default bash 3.2,
# which has no `declare -A`; the plugin-system lib follows the same constraint).
# Lookups are linear scans over the ~10-entry rule set — negligible cost.
# ---------------------------------------------------------------------------

SPEC_RULE_IDS=()
SPEC_RULE_SEVERITY=()    # parallel to SPEC_RULE_IDS by index
SPEC_RULE_MANDATORY=()   # parallel
SPEC_RULE_APPLIES=()     # parallel

# _spec_rule_index <rule-id> — echo the index of a rule id, or empty if absent.
_spec_rule_index() {
    local want="$1" i=0
    for i in "${!SPEC_RULE_IDS[@]}"; do
        if [ "${SPEC_RULE_IDS[$i]}" = "$want" ]; then
            printf '%s' "$i"
            return 0
        fi
    done
    return 1
}

load_rules() {
    local rules_file="$1"
    [ -n "$rules_file" ] || usage_die "load_rules: rules file path required"
    [ -f "$rules_file" ] || usage_die "rule registry not found: $rules_file"

    SPEC_RULE_IDS=()
    SPEC_RULE_SEVERITY=()
    SPEC_RULE_MANDATORY=()
    SPEC_RULE_APPLIES=()

    local idx=-1 line key val
    while IFS= read -r line; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        # New rule block: "- id: <value>"
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*id:[[:space:]]*(.+)$ ]]; then
            local cur_id="${BASH_REMATCH[1]}"
            cur_id="${cur_id%"${cur_id##*[![:space:]]}"}"   # rtrim
            SPEC_RULE_IDS+=("$cur_id")
            idx=$((idx + 1))
            SPEC_RULE_SEVERITY[$idx]="info"
            SPEC_RULE_MANDATORY[$idx]="false"
            SPEC_RULE_APPLIES[$idx]=""
            continue
        fi
        [ "$idx" -ge 0 ] || continue
        if [[ "$line" =~ ^[[:space:]]+([a-z_]+):[[:space:]]*(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            val="${val%"${val##*[![:space:]]}"}"
            case "$key" in
                severity)   SPEC_RULE_SEVERITY[$idx]="$val" ;;
                mandatory)  SPEC_RULE_MANDATORY[$idx]="$val" ;;
                applies_to) SPEC_RULE_APPLIES[$idx]="$val" ;;
            esac
        fi
    done < "$rules_file"

    [ "${#SPEC_RULE_IDS[@]}" -gt 0 ] || usage_die "rule registry has no rules: $rules_file"
    return 0
}

is_mandatory() {
    local i
    i="$(_spec_rule_index "$1")" || return 1
    [ "${SPEC_RULE_MANDATORY[$i]}" = "true" ]
}

rule_severity() {
    local i
    if i="$(_spec_rule_index "$1")"; then
        printf '%s\n' "${SPEC_RULE_SEVERITY[$i]}"
    else
        printf 'info\n'
    fi
}

rule_exists() {
    _spec_rule_index "$1" >/dev/null 2>&1
}

rule_applies_to_level() {
    # rule_applies_to_level <rule-id> <Ln>
    local rid="$1" level="$2" i
    i="$(_spec_rule_index "$rid")" || return 1
    case " ${SPEC_RULE_APPLIES[$i]} " in
        *"$level"*) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# effective_ruleset — resolve --rules / --ignore against the loaded registry.
# Populates SPEC_EFFECTIVE_RULES. Configuration errors (R4) exit 2:
#   - unknown rule id in --rules or --ignore
#   - attempt to --ignore a mandatory rule
#   - empty effective set after filtering
# ---------------------------------------------------------------------------

SPEC_EFFECTIVE_RULES=()

effective_ruleset() {
    local include="$SPEC_RULES_INCLUDE" ignore="$SPEC_RULES_IGNORE"
    local -a want=()
    local r tok

    if [ -n "$include" ]; then
        # IFS scoped to the read builtin only — never set globally (S1).
        local -a _inc=()
        IFS=',' read -ra _inc <<< "$include"
        for tok in "${_inc[@]}"; do
            tok="${tok// /}"
            [ -n "$tok" ] || continue
            rule_exists "$tok" || usage_die "unknown rule id in --rules: $tok"
            want+=("$tok")
        done
    else
        want=("${SPEC_RULE_IDS[@]}")
    fi

    local -a drop=()
    if [ -n "$ignore" ]; then
        local -a _ign=()
        IFS=',' read -ra _ign <<< "$ignore"
        for tok in "${_ign[@]}"; do
            tok="${tok// /}"
            [ -n "$tok" ] || continue
            rule_exists "$tok" || usage_die "unknown rule id in --ignore: $tok"
            is_mandatory "$tok" && usage_die "cannot --ignore mandatory rule: $tok"
            drop+=("$tok")
        done
    fi

    SPEC_EFFECTIVE_RULES=()
    for r in "${want[@]}"; do
        local skip=0 d
        if [ "${#drop[@]}" -gt 0 ]; then
            for d in "${drop[@]}"; do
                [ "$r" = "$d" ] && { skip=1; break; }
            done
        fi
        [ "$skip" -eq 0 ] && SPEC_EFFECTIVE_RULES+=("$r")
    done

    [ "${#SPEC_EFFECTIVE_RULES[@]}" -gt 0 ] || usage_die "empty effective ruleset after --rules/--ignore filtering"
    return 0
}

rule_enabled() {
    local target="$1" r
    for r in "${SPEC_EFFECTIVE_RULES[@]}"; do
        [ "$r" = "$target" ] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Graph helpers. Pure-text scan of a markdown artefact.
# ---------------------------------------------------------------------------

# collect_d_req <file> — print "lineno<TAB>D-REQ-NN" for each declaration, in order.
# Accepts both canonical forms: the `#### D-REQ-NN: …` heading and the
# `- **D-REQ-NN** — …` bold-list bullet (see schema-regex.sh D_REQ_ID_RE).
collect_d_req() {
    local file="$1"
    [ -f "$file" ] || return 0
    grep -nE "$D_REQ_ID_RE" "$file" 2>/dev/null \
        | sed -E 's/^([0-9]+):.*(D-REQ-[0-9]{2}).*$/\1\t\2/'
}

# collect_covers <file> — print "lineno<TAB>D-REQ-NN" for each id in each Covers line.
collect_covers() {
    local file="$1"
    [ -f "$file" ] || return 0
    grep -nE "$COVERS_LINE_RE" "$file" 2>/dev/null | while IFS= read -r line; do
        local lineno="${line%%:*}"
        local body="${line#*:}"
        # extract every D-REQ-NN token on the line
        printf '%s\n' "$body" | grep -oE "$D_REQ_REF_RE" | while IFS= read -r ref; do
            printf '%s\t%s\n' "$lineno" "$ref"
        done
    done
}

# collect_vac <file> — print "lineno<TAB>V-AC-label" for each V-AC heading/item.
collect_vac() {
    local file="$1"
    [ -f "$file" ] || return 0
    grep -nE '\bV-AC-[0-9]+' "$file" 2>/dev/null \
        | grep -oE '^[0-9]+:.*V-AC-[0-9]+(\.[0-9]+)?' \
        | sed -E 's/^([0-9]+):.*(V-AC-[0-9]+(\.[0-9]+)?).*$/\1\t\2/' \
        | sort -u
}

# collect_verifies <file> — print "lineno<TAB>V-AC-N" for explicit plan edges.
collect_verifies() {
    local file="$1"
    [ -f "$file" ] || return 0
    grep -nE "$VERIFIES_LINE_RE" "$file" 2>/dev/null | while IFS= read -r line; do
        local lineno="${line%%:*}"
        local body="${line#*:}"
        printf '%s\n' "$body" | grep -oE "$V_AC_REF_RE" | while IFS= read -r ref; do
            printf '%s\t%s\n' "$lineno" "$ref"
        done
    done
}

# collect_evidence <file...> — print "path:lineno<TAB>V-AC-N" for explicit evidence edges.
collect_evidence() {
    local file line lineno body ref
    for file in "$@"; do
        [ -f "$file" ] || continue
        while IFS= read -r line; do
            lineno="${line%%:*}"
            body="${line#*:}"
            while IFS= read -r ref; do
                [ -n "$ref" ] && printf '%s:%s\t%s\n' "${file##*/}" "$lineno" "$ref"
            done < <(printf '%s\n' "$body" | grep -oE "$V_AC_REF_RE")
        done < <(grep -nE "$EVIDENCE_LINE_RE" "$file" 2>/dev/null)
    done
}

# collect_expectation_links <file>
# Prints: wish_id<TAB>linked_vac<TAB>status<TAB>valid_operator_override
collect_expectation_links() {
    local file="$1"
    [ -f "$file" ] || return 0
    python3 - "$file" <<'PYEOF'
import re
import sys

path = sys.argv[1]
items = []
cur = None
in_status = False

def flush():
    if cur and cur["wish"]:
        valid_override = (
            cur["status"] in {"partial", "missed"}
            and len(cur["override"].strip()) >= 10
            and cur["override_by"] == "operator"
        )
        print("\t".join((
            cur["wish"],
            cur["vac"],
            cur["status"],
            "yes" if valid_override else "no",
        )))

with open(path, encoding="utf-8") as fh:
    for raw in fh:
        line = raw.rstrip("\n")
        m = re.search(r"\bwish_id:\s*(\S+)", line)
        if m:
            flush()
            cur = {
                "wish": m.group(1),
                "vac": "",
                "status": "pending",
                "override": "",
                "override_by": "",
            }
            in_status = False
            continue
        if not cur:
            continue
        if "Связанный AC из PRD:" in line:
            vm = re.search(r"V-AC-\d+(?:\.\d+)?", line)
            cur["vac"] = vm.group(0) if vm else ""
        elif re.match(r"\s*-\s*override:\s*", line):
            cur["override"] = line.split("override:", 1)[1].strip()
        elif re.match(r"\s*-\s*override_by:\s*", line):
            cur["override_by"] = line.split("override_by:", 1)[1].strip()
        elif "Текущий статус" in line:
            in_status = True
        elif in_status:
            sm = re.match(r"\s*-\s*(pending|met|partial|missed|n-a|deleted)\s*$", line)
            if sm:
                cur["status"] = sm.group(1)
                in_status = False
flush()
PYEOF
}
