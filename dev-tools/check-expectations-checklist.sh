#!/usr/bin/env bash
# check-expectations-checklist.sh — expectations checklist validator (F2/F3).
#
# Validates the structural shape of `datarim/tasks/{ID}-expectations.md` files
# produced at `/dr-prd` (L3+) or `/dr-plan` (L2 without PRD) and consumed at
# `/dr-qa`, `/dr-compliance`, `/dr-archive`. Three modes:
#
#   --task <ID>     — structural validation of a single expectations file
#                     (frontmatter shape, '## Ожидания' heading, per-item
#                     wish_id/status/История format).
#                     Exit 0 = OK, 1 = malformed/missing, 2 = usage error.
#
#   --verify <ID>   — verify-routing mode for QA/COMPLIANCE/ARCHIVE: read the
#                     file's per-item Текущий статус and override values, then
#                     emit a verdict on stdout:
#                       PASS              — every item is met/n-a/pending/deleted
#                       CONDITIONAL_PASS  — partial/missed items all carry an
#                                            operator override (≥10 chars)
#                       BLOCKED           — ≥1 partial/missed item without
#                                            a valid override; CTA emits
#                                            `/dr-do {ID} --focus-items <wish_ids>`
#                     Exit 0 = PASS / CONDITIONAL_PASS, 1 = BLOCKED or malformed,
#                     2 = usage error.
#
#   --all           — scan task-descriptions and emit advisory findings for
#                     L3+ tasks that lack an expectations file. Severity
#                     ladder: info (<30d) → warn (≥30d). Exit code is always 0.
#
# Source-of-truth contract: skills/expectations-checklist/SKILL.md.
#
set -uo pipefail

VERSION="1.1.0"
SCRIPT_NAME="check-expectations-checklist.sh"

# TUNE-0266 Phase 4: pivot date for "all wishes evidence_type=static" advisory.
# Tasks whose expectations frontmatter carries captured_at < this date are
# treated as legacy and skipped by the warn-all-static check. Override via
# DATARIM_TUNE_0266_PIVOT_DATE env var (ISO YYYY-MM-DD).
TUNE_0266_PIVOT_DATE="2026-05-23"

usage() {
    cat <<EOF
Usage:
  $SCRIPT_NAME --task   <TASK-ID> [--root <path>] [--report]
  $SCRIPT_NAME --verify <TASK-ID> [--root <path>]
  $SCRIPT_NAME --all              [--root <path>] [--today YYYY-MM-DD]

Options:
  --task <ID>          Structural validation of one expectations file (exit 0/1).
  --verify <ID>        Verify-routing verdict (PASS/CONDITIONAL_PASS/BLOCKED).
  --all                Scan task-descriptions for missing expectations (advisory, exit 0).
  --root <path>        Repository root containing datarim/ (default: pwd).
  --report             Human-readable detail output (single-task mode).
  --today YYYY-MM-DD   Override today's date for soft-window tests.
  --help               Show this help and exit 0.
  --version            Print version and exit 0.

Schema v3 fields (optional per-wish, opt-in — requires schema_version: 3 in frontmatter):
  verification_mode: one-off | reproducible
    Distinguishes a one-off manual check (default when absent) from a
    reproducible/wired check. Bad enum value → ERROR.
  evidence_artifact: <path | test-id | CI-job-name>
    Required when verification_mode: reproducible. Resolved two ways:
      1. test -f (absolute or repo-root-relative)
      2. grep -rqF across *.bats *.sh *.yml *.yaml under repo root
    Missing or unresolvable artifact → ERROR verification-not-wired.
    Existing file scanned for stub literals (it.skip, xit(, .todo,
    expect(true).toBe(true), test.skip, @pytest.mark.skip) — advisory
    finding evidence-artifact-is-stub when file appears stub-only.

Exit codes:
  0   PASS / OK / advisory findings only
  1   structural error OR BLOCKED verdict
  2   usage / internal error
EOF
}

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
MODE=""
TASK_ID=""
ROOT=""
REPORT=0
TODAY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --task)
            MODE="task"; shift
            TASK_ID="${1:-}"
            [ -z "$TASK_ID" ] && { echo "ERROR: --task requires a TASK-ID" >&2; exit 2; }
            ;;
        --verify)
            MODE="verify"; shift
            TASK_ID="${1:-}"
            [ -z "$TASK_ID" ] && { echo "ERROR: --verify requires a TASK-ID" >&2; exit 2; }
            ;;
        --all)
            MODE="all"
            ;;
        --root)
            shift; ROOT="${1:-}"
            ;;
        --report)
            REPORT=1
            ;;
        --today)
            shift; TODAY="${1:-}"
            ;;
        --help|-h)
            usage; exit 0
            ;;
        --version)
            echo "$SCRIPT_NAME $VERSION"; exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2
            ;;
    esac
    shift
done

[ -z "$MODE" ] && { echo "ERROR: one of --task, --verify or --all is required" >&2; exit 2; }
# Default --root via the canonical resolver so a nested cwd still finds the
# repo-root. Fail-soft: fall back to $PWD if the resolver is absent.
if [ -z "$ROOT" ]; then
    _exp_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib" 2>/dev/null && pwd)"
    if [ -n "$_exp_lib" ] && [ -f "$_exp_lib/resolve-datarim-root.sh" ]; then
        # shellcheck source=../scripts/lib/resolve-datarim-root.sh
        . "$_exp_lib/resolve-datarim-root.sh"
        ROOT="$(resolve_datarim_root 2>/dev/null || true)"
    fi
    [ -z "$ROOT" ] && ROOT="$(pwd)"
fi
[ -z "$TODAY" ] && TODAY="$(date +%Y-%m-%d)"

TASKS_DIR="$ROOT/datarim/tasks"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

extract_frontmatter_field() {
    local file="$1" field="$2"
    awk -v key="$field" '
        /^---$/ { if (in_fm) exit; in_fm=1; next }
        in_fm {
            if (match($0, "^" key ":[ \t]*")) {
                print substr($0, RLENGTH + 1)
                exit
            }
        }
    ' "$file"
}

days_between() {
    local from="$1" to="$2"
    local from_epoch to_epoch
    from_epoch=$(date -j -f "%Y-%m-%d" "$from" +%s 2>/dev/null || true)
    to_epoch=$(date -j -f "%Y-%m-%d" "$to" +%s 2>/dev/null || true)
    if [ -z "$from_epoch" ] || [ -z "$to_epoch" ]; then
        from_epoch=$(date -d "$from" +%s 2>/dev/null || echo "")
        to_epoch=$(date -d "$to" +%s 2>/dev/null || echo "")
    fi
    if [ -z "$from_epoch" ] || [ -z "$to_epoch" ]; then
        awk -v f="$from" -v t="$to" '
            function jd(s,    y,m,d,a) {
                split(s, a, "-")
                y=a[1]+0; m=a[2]+0; d=a[3]+0
                return d - 32075 + int(1461*(y+4800+int((m-14)/12))/4) \
                    + int(367*(m-2-int((m-14)/12)*12)/12) \
                    - int(3*int((y+4900+int((m-14)/12))/100)/4)
            }
            BEGIN { diff = jd(t) - jd(f); if (diff < 0) diff = -diff; print diff }
        '
        return
    fi
    local diff=$(( to_epoch - from_epoch ))
    [ "$diff" -lt 0 ] && diff=$(( -diff ))
    echo $(( diff / 86400 ))
}

# ---------------------------------------------------------------------------
# Core: per-item parser. Emits a pipe-separated table to stdout for verify
# mode and structural errors to stderr. Exit 0 if zero errors, 1 otherwise.
#
# Output stream (stdout):
#   <item_num>|<wish_id>|<status>|<override_len>|<override_by>|<override_class>|<override_artifact>|<verification_mode>|<evidence_artifact>|<evidence_type>|<success_criterion>
#
# The verification_mode / evidence_artifact fields are emitted in the pipe-
# separated row so that a bash post-parse loop (not awk system()) can do the
# two-tier evidence_artifact resolution (test -f + grep). awk system() requires
# shell escaping of arbitrary user-supplied paths and grep patterns; delegating
# to a bash loop is safer and easier to maintain.
#
# Errors (stderr):
#   ERROR: <file>: <item N | section> <reason>
# ---------------------------------------------------------------------------

parse_items() {
    local file="$1"
    local schema="${2:-1}"
    awk -v f="$file" -v schema="$schema" '
        BEGIN {
            in_section = 0; current_item = 0; total_items = 0; errors = 0
            wish_id = ""; status = ""; override_text = ""; evidence_type = ""
            override_by = ""; override_class = ""; override_artifact = ""
            verification_mode = ""; evidence_artifact = ""; success_criterion = ""
            history_count = 0; has_history_heading = 0; has_status_heading = 0
            in_history = 0; in_status = 0
        }

        /^## Ожидания[ \t]*$/ {
            in_section = 1; next
        }
        /^## / && in_section {
            if (current_item) emit_item()
            current_item = 0
            in_section = 0
            in_history = 0; in_status = 0
            next
        }

        in_section {
            # New item header: `- **N. Title**`
            if (match($0, /^- \*\*[0-9]+\. /)) {
                if (current_item) emit_item()
                total_items++
                current_item = total_items
                wish_id = ""; status = ""; override_text = ""; evidence_type = ""
                override_by = ""; override_class = ""; override_artifact = ""
                verification_mode = ""; evidence_artifact = ""; success_criterion = ""
                history_count = 0; has_history_heading = 0; has_status_heading = 0
                in_history = 0; in_status = 0
                next
            }
            if (current_item) {
                if (match($0, /^  - wish_id:[ \t]*/)) {
                    wish_id = substr($0, RLENGTH + 1)
                    sub(/[ \t]+$/, "", wish_id)
                    in_history = 0; in_status = 0; next
                }
                if (match($0, /^  - evidence_type:[ \t]*/)) {
                    evidence_type = substr($0, RLENGTH + 1)
                    sub(/[ \t]+$/, "", evidence_type)
                    in_history = 0; in_status = 0; next
                }
                if (match($0, /^  - verification_mode:[ \t]*/)) {
                    verification_mode = substr($0, RLENGTH + 1)
                    sub(/[ \t]+$/, "", verification_mode)
                    in_history = 0; in_status = 0; next
                }
                if (match($0, /^  - evidence_artifact:[ \t]*/)) {
                    evidence_artifact = substr($0, RLENGTH + 1)
                    sub(/[ \t]+$/, "", evidence_artifact)
                    in_history = 0; in_status = 0; next
                }
                # Capture success criterion for heuristic-advisory (v3 empirical wishes).
                if (match($0, /^  - Как проверить \(success criterion\):[ \t]*/)) {
                    success_criterion = substr($0, RLENGTH + 1)
                    sub(/[ \t]+$/, "", success_criterion)
                    in_history = 0; in_status = 0; next
                }
                if (match($0, /^  - override:[ \t]*/)) {
                    override_text = substr($0, RLENGTH + 1)
                    sub(/[ \t]+$/, "", override_text)
                    in_history = 0; in_status = 0; next
                }
                if (match($0, /^  - override_by:[ \t]*/)) {
                    override_by = substr($0, RLENGTH + 1)
                    sub(/[ \t]+$/, "", override_by)
                    in_history = 0; in_status = 0; next
                }
                if (match($0, /^  - override_class:[ \t]*/)) {
                    override_class = substr($0, RLENGTH + 1)
                    sub(/[ \t]+$/, "", override_class)
                    in_history = 0; in_status = 0; next
                }
                if (match($0, /^  - override_artifact:[ \t]*/)) {
                    override_artifact = substr($0, RLENGTH + 1)
                    sub(/[ \t]+$/, "", override_artifact)
                    in_history = 0; in_status = 0; next
                }
                if ($0 ~ /^  - #### История статусов/) {
                    has_history_heading = 1; in_history = 1; in_status = 0; next
                }
                if ($0 ~ /^  - #### Текущий статус/) {
                    has_status_heading = 1; in_history = 0; in_status = 1; next
                }
                if (in_history && match($0, /^    - /)) {
                    history_count++
                    line = substr($0, 7)
                    if (!(line ~ /·.*·.*·.*reason:/)) {
                        printf "ERROR: %s: item %d malformed История статусов line: %s\n", \
                            f, current_item, line > "/dev/stderr"
                        errors++
                    }
                    next
                }
                if (in_status && match($0, /^    - /)) {
                    status = substr($0, 7)
                    sub(/[ \t]+$/, "", status)
                    in_status = 0; next
                }
            }
        }

        END {
            if (current_item) emit_item()
            if (total_items == 0) {
                printf "ERROR: %s: no items found under ## Ожидания (file appears empty)\n", f > "/dev/stderr"
                errors++
            }
            exit (errors > 0 ? 1 : 0)
        }

        function emit_item(    ovr_len) {
            if (wish_id == "") {
                printf "ERROR: %s: item %d missing wish_id\n", f, current_item > "/dev/stderr"
                errors++
            }
            if (!has_history_heading) {
                printf "ERROR: %s: item %d missing #### История статусов heading\n", f, current_item > "/dev/stderr"
                errors++
            } else if (history_count == 0) {
                printf "ERROR: %s: item %d has empty История статусов (need >=1 entry)\n", f, current_item > "/dev/stderr"
                errors++
            }
            if (!has_status_heading) {
                printf "ERROR: %s: item %d missing #### Текущий статус heading\n", f, current_item > "/dev/stderr"
                errors++
            }
            if (status == "") {
                printf "ERROR: %s: item %d missing Текущий статус value\n", f, current_item > "/dev/stderr"
                errors++
            } else if (status != "pending" && status != "met" && status != "partial" \
                   && status != "missed" && status != "n-a" && status != "deleted") {
                printf "ERROR: %s: item %d status not in enum: %s\n", f, current_item, status > "/dev/stderr"
                errors++
            }
            # v2 schema: evidence_type required + enum (empirical|static|measurement).
            # See skills/expectations-checklist/SKILL.md § Item rules.
            if (schema == "2" || schema == "3") {
                if (evidence_type == "") {
                    printf "ERROR: %s: item %d missing evidence_type (required in schema_version=2/3)\n", f, current_item > "/dev/stderr"
                    errors++
                } else if (evidence_type != "empirical" && evidence_type != "static" \
                       && evidence_type != "measurement") {
                    printf "ERROR: %s: item %d evidence_type not in enum: %s (allowed: empirical|static|measurement)\n", f, current_item, evidence_type > "/dev/stderr"
                    errors++
                }
            }
            # v3 schema: verification_mode optional enum; reproducible requires evidence_artifact.
            # Hard error for bad enum and for reproducible-without-artifact.
            # advisory heuristic (missing mode on empirical with world-state text) and
            # stub-artifact check are done in the bash post-parse loop — they need file I/O.
            if (schema == "3" && verification_mode != "") {
                if (verification_mode != "one-off" && verification_mode != "reproducible") {
                    printf "ERROR: %s: item %d verification_mode not in enum: %s (allowed: one-off|reproducible)\n", \
                        f, current_item, verification_mode > "/dev/stderr"
                    errors++
                }
                if (verification_mode == "reproducible" && evidence_artifact == "") {
                    printf "ERROR: %s: item %d verification-not-wired: %s (reproducible requires evidence_artifact)\n", \
                        f, current_item, wish_id > "/dev/stderr"
                    errors++
                }
            }
            ovr_len = length(override_text)
            if (override_by == "") override_by = "-"
            if (override_class == "") override_class = "-"
            if (override_artifact == "") override_artifact = "-"
            if (verification_mode == "") verification_mode = "-"
            if (evidence_artifact == "") evidence_artifact = "-"
            # Encode success_criterion: replace | with \x01 so pipe-split is safe.
            sc = success_criterion; gsub(/\|/, "\x01", sc)
            printf "%d|%s|%s|%d|%s|%s|%s|%s|%s|%s|%s\n", \
                current_item, wish_id, status, ovr_len, override_by, override_class, override_artifact, \
                verification_mode, evidence_artifact, evidence_type, sc
        }
    ' "$file"
}

# ---------------------------------------------------------------------------
# Single-task structural validation
# ---------------------------------------------------------------------------

validate_single_task() {
    local id="$1"
    local file="$TASKS_DIR/${id}-expectations.md"

    if [ ! -f "$file" ]; then
        echo "ERROR: expectations file missing for $id (expected $file)" >&2
        if [ "$REPORT" -eq 1 ]; then
            echo "  Run /dr-prd or /dr-plan to seed expectations from PRD"
            echo "  acceptance criteria + init-task. Contract in"
            echo "  skills/expectations-checklist/SKILL.md."
        fi
        return 1
    fi

    local errors=0 val

    for field in task_id artifact schema_version captured_at captured_by status; do
        val=$(extract_frontmatter_field "$file" "$field")
        if [ -z "$val" ]; then
            echo "ERROR: $file: frontmatter missing required field '$field'" >&2
            errors=$(( errors + 1 ))
        fi
    done

    val=$(extract_frontmatter_field "$file" "artifact")
    if [ -n "$val" ] && [ "$val" != "expectations" ]; then
        echo "ERROR: $file: frontmatter artifact must be 'expectations', got '$val'" >&2
        errors=$(( errors + 1 ))
    fi

    val=$(extract_frontmatter_field "$file" "schema_version")
    schema_v="$val"
    if [ -n "$val" ] && [ "$val" != "1" ] && [ "$val" != "2" ] && [ "$val" != "3" ]; then
        echo "ERROR: $file: schema_version must be '1', '2', or '3', got '$val'" >&2
        errors=$(( errors + 1 ))
    fi
    # v1 legacy deprecation warning (TUNE-0266: 12-month sunset, see
    # skills/expectations-checklist/SKILL.md § Backwards-compatibility window).
    if [ "$val" = "1" ]; then
        echo "DEPRECATION: $file: schema_version=1 — upgrade to v2 at next edit. Sunset: 2027-05-23 (12 months from TUNE-0266 archive). See documentation/migration-v1-v2.md." >&2
    fi

    val=$(extract_frontmatter_field "$file" "task_id")
    if [ -n "$val" ] && ! [[ "$val" =~ ^[A-Z]{2,10}-[0-9]{4}(-[A-Za-z0-9]+)*$ ]]; then
        echo "ERROR: $file: task_id '$val' does not match {PREFIX-NNNN} or {PREFIX-NNNN-suffix...}" >&2
        errors=$(( errors + 1 ))
    fi

    if ! grep -q '^## Ожидания[[:space:]]*$' "$file"; then
        echo "ERROR: $file: missing required heading '## Ожидания'" >&2
        errors=$(( errors + 1 ))
    fi

    # Item-level parse — emits to stdout (captured here for v3 post-parse) + stderr.
    # schema_v passed through to enable evidence_type/verification_mode checks.
    local items_out
    items_out=$(parse_items "$file" "${schema_v:-1}" 2>/tmp/_cec_stderr_$$) || errors=$(( errors + 1 ))
    # Pipe parse stderr to our stderr so callers see it.
    cat /tmp/_cec_stderr_$$ >&2 2>/dev/null || true
    rm -f /tmp/_cec_stderr_$$

    # Post-parse bash loop: v3 evidence_artifact resolution + stub advisory + heuristic advisory.
    # Done here (not in awk) because we need test -f, grep, and file scanning — unsafe inside awk system().
    if [ "${schema_v:-1}" = "3" ] && [ -n "$items_out" ]; then
        # Determine repo root for evidence_artifact resolution (two-tier: test -f, then grep).
        local repo_root
        repo_root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null || echo "$ROOT")

        while IFS='|' read -r _idx _wid _st _ovrl _ovby _ovcl _ovart vmode earl etype sc; do
            [ -z "$_wid" ] && continue

            # Two-tier evidence_artifact resolution for reproducible wishes.
            if [ "$vmode" = "reproducible" ] && [ "$earl" != "-" ] && [ -n "$earl" ]; then
                local resolved=0
                # Tier 1: direct file existence (absolute or repo-root relative).
                if [ -f "$earl" ] || [ -f "$repo_root/$earl" ]; then
                    resolved=1
                    # Stub-literal advisory: scan file for stub-only patterns.
                    local target_file="$earl"
                    [ ! -f "$target_file" ] && target_file="$repo_root/$earl"
                    # grep -c prints a count (0 on no-match) AND exits non-zero on
                    # no-match; `|| true` swallows the exit without the classic
                    # `|| echo 0` double-zero bug (which yields "0\n0" → integer-
                    # expression errors downstream).
                    local stub_lines non_blank
                    stub_lines=$(grep -cE '(it\.skip|xit\(|\.todo|expect\(true\)\.toBe\(true\)|test\.skip|@pytest\.mark\.skip)' "$target_file" 2>/dev/null || true)
                    non_blank=$(grep -cE '\S' "$target_file" 2>/dev/null || true)
                    [ -z "$stub_lines" ] && stub_lines=0
                    [ -z "$non_blank" ] && non_blank=0
                    [ "$non_blank" -eq 0 ] && non_blank=1
                    # Advisory only when stub_lines makes up all non-blank content.
                    if [ "$stub_lines" -gt 0 ] && [ "$stub_lines" -eq "$non_blank" ]; then
                        echo "ADVISORY: $file: item ${_idx} evidence-artifact-is-stub: ${_wid} (all non-blank lines are stub literals)" >&2
                    fi
                else
                    # Tier 2: grep -rqF across test/CI files under repo root.
                    if grep -rqF "$earl" --include="*.bats" --include="*.sh" \
                           --include="*.yml" --include="*.yaml" "$repo_root" 2>/dev/null; then
                        resolved=1
                    fi
                fi
                if [ "$resolved" -eq 0 ]; then
                    echo "ERROR: $file: item ${_idx} verification-not-wired: ${_wid} (evidence_artifact '$earl' not found by file-path or grep)" >&2
                    errors=$(( errors + 1 ))
                fi
            fi

            # Heuristic advisory (v3, empirical, no verification_mode, world-state predicates in criterion).
            # Best-effort only — NEVER a hard error. Suppressed when verification_mode is already set.
            if [ "$vmode" = "-" ] && [ "$etype" = "empirical" ]; then
                # Restore pipe-placeholder back to space for matching.
                local criterion
                criterion=$(printf '%s' "$sc" | tr '\x01' '|')
                if printf '%s' "$criterion" | grep -qiE \
                    'https?://|\bHTTP\b|\bcurl\b|redirect|\bprod\b|production|статус|status|перед тем как|before status|перед статусом|/app/|deploy'; then
                    echo "ADVISORY: $file: item ${_idx} verification-mode-suggested-reproducible: ${_wid} (empirical wish with world-state criterion — consider verification_mode: reproducible + evidence_artifact)" >&2
                fi
            fi
        done <<< "$items_out"
    fi

    if [ "$errors" -gt 0 ]; then
        if [ "$REPORT" -eq 1 ]; then
            echo "  $errors validation error(s) — see contract in"
            echo "  skills/expectations-checklist/SKILL.md § Item Schema."
        fi
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Verify-routing mode
# ---------------------------------------------------------------------------

verify_routing() {
    local id="$1"
    local file="$TASKS_DIR/${id}-expectations.md"

    if [ ! -f "$file" ]; then
        echo "ERROR: expectations file missing for $id (expected $file)" >&2
        echo "BLOCKED: expectations checklist absent — run /dr-prd or /dr-plan first"
        return 1
    fi

    # Validate structure first; structural error → BLOCKED.
    if ! validate_single_task "$id" >/dev/null 2>&1; then
        echo "BLOCKED: expectations file fails structural validation; run --task --report for detail" >&2
        return 1
    fi

    local schema_v
    schema_v=$(extract_frontmatter_field "$file" "schema_version")
    local items
    items=$(parse_items "$file" "${schema_v:-1}" 2>/dev/null) || true

    local blocking=()
    local has_partial_or_missed=0
    local backlog_idx="$ROOT/datarim/backlog.md"
    local tasks_idx="$ROOT/datarim/tasks.md"

    # A legitimate-deferral artefact is a follow-up / blocked_by ID that actually
    # exists in the knowledge base. Prose is not an artefact.
    artefact_exists() {
        local art="$1"
        local id
        # extract the first TASK-ID-shaped token (e.g. ABC-1234, optional -FU-slug)
        id="$(printf '%s' "$art" | grep -oiE '[A-Z]+-[0-9]{4}' | head -n1 || true)"
        [ -z "$id" ] && return 1
        if [ -f "$backlog_idx" ] && grep -qiE "(^|[^A-Za-z0-9-])${id}([^A-Za-z0-9-]|$)" "$backlog_idx"; then return 0; fi
        if [ -f "$tasks_idx" ]   && grep -qiE "(^|[^A-Za-z0-9-])${id}([^A-Za-z0-9-]|$)" "$tasks_idx";   then return 0; fi
        return 1
    }

    while IFS='|' read -r _idx wish_id status ovr_len ovr_by ovr_class ovr_artifact _vmode _earl _etype _sc; do
        [ -z "$status" ] && continue
        case "$status" in
            met|n-a|pending|deleted)
                ;;
            partial|missed)
                has_partial_or_missed=1
                # Floor: an override must still carry >=10 chars of reason.
                if [ "${ovr_len:-0}" -lt 10 ]; then
                    blocking+=("$wish_id")
                    continue
                fi
                # Authorship gate (anti-self-certification):
                #   operator-authored  -> accept (operator may authorise anything)
                #   agent-authored      -> require an allowed class AND a verifiable artefact
                #   absent override_by  -> treat as agent (most restrictive; back-compat)
                case "${ovr_by:--}" in
                    operator)
                        ;;  # accept
                    agent|-|"")
                        case "${ovr_class:--}" in
                            time-dependent|external-blocker|operator-authorized|plan-scope-boundary) : ;;
                            *) blocking+=("$wish_id"); continue ;;
                        esac
                        if ! artefact_exists "${ovr_artifact:--}"; then
                            blocking+=("$wish_id"); continue
                        fi
                        ;;
                    *)
                        blocking+=("$wish_id"); continue
                        ;;
                esac
                ;;
            *)
                # Already caught by structural validation; defensive guard.
                blocking+=("$wish_id")
                ;;
        esac
    done <<< "$items"

    if [ "${#blocking[@]}" -gt 0 ]; then
        local focus
        focus=$(IFS=,; echo "${blocking[*]}")  # nosemgrep: bash.lang.security.ifs-tampering.ifs-tampering
        echo "BLOCKED: ${#blocking[@]} expectation(s) require resolution"
        echo "Focus items: $focus"
        echo "Next step:   /dr-do $id --focus-items $focus"
        return 1
    fi

    if [ "$has_partial_or_missed" -eq 1 ]; then
        echo "CONDITIONAL_PASS: all partial/missed items carry an operator-authored or artefact-backed override"
        return 0
    fi

    echo "PASS: all expectation items met / n-a / pending / deleted"
    return 0
}

# ---------------------------------------------------------------------------
# Multi-task advisory scan
# ---------------------------------------------------------------------------

scan_all_tasks() {
    [ ! -d "$TASKS_DIR" ] && return 0

    local desc id complexity status legacy created exp_file age severity
    local pivot captured_at total_wishes static_wishes
    pivot="${DATARIM_TUNE_0266_PIVOT_DATE:-$TUNE_0266_PIVOT_DATE}"
    shopt -s nullglob
    for desc in "$TASKS_DIR"/*-task-description.md; do
        id="$(basename "$desc")"
        id="${id%-task-description.md}"
        exp_file="$TASKS_DIR/${id}-expectations.md"

        # TUNE-0266 Phase 4: tasks WITH expectations — advisory warn when every
        # wish carries evidence_type: static. Single-wish skeletons (L1) and
        # legacy tasks are exempt. Legacy = legacy:true in description frontmatter
        # OR expectations captured_at strictly before TUNE_0266_PIVOT_DATE.
        if [ -f "$exp_file" ]; then
            legacy=$(extract_frontmatter_field "$desc" "legacy")
            [ "$legacy" = "true" ] && continue

            captured_at=$(extract_frontmatter_field "$exp_file" "captured_at")
            if [ -n "$captured_at" ] && [[ "$captured_at" < "$pivot" ]]; then
                continue
            fi

            total_wishes=$(grep -cE '^  - wish_id:' "$exp_file" || true)
            static_wishes=$(grep -cE '^  - evidence_type:[[:space:]]*static[[:space:]]*$' "$exp_file" || true)
            if [ "$total_wishes" -ge 2 ] && [ "$total_wishes" -eq "$static_wishes" ]; then
                echo "WARNING: $id all wishes have evidence_type: static — consider adding empirical/measurement evidence"
            fi
            continue
        fi

        complexity=$(extract_frontmatter_field "$desc" "complexity")
        case "$complexity" in
            L3|L4) ;;
            *) continue ;;
        esac

        status=$(extract_frontmatter_field "$desc" "status")
        case "$status" in
            archived|completed|cancelled) continue ;;
        esac

        legacy=$(extract_frontmatter_field "$desc" "legacy")
        [ "$legacy" = "true" ] && continue

        created=$(extract_frontmatter_field "$desc" "created")
        if [ -z "$created" ]; then
            echo "info: $id expectations missing (no 'created' date in description)"
            continue
        fi

        age=$(days_between "$created" "$TODAY")
        if [ "$age" -lt 30 ]; then
            severity="info"
        else
            severity="warn"
        fi
        echo "$severity: $id expectations missing (task age ${age}d; rolling 30d soft window, complexity $complexity)"
    done
    shopt -u nullglob
    return 0
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "$MODE" in
    task)
        validate_single_task "$TASK_ID"; exit $?
        ;;
    verify)
        verify_routing "$TASK_ID"; exit $?
        ;;
    all)
        scan_all_tasks; exit 0
        ;;
    *)
        usage >&2; exit 2
        ;;
esac
