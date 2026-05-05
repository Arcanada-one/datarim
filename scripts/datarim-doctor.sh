#!/usr/bin/env bash
# datarim-doctor.sh — index-style schema migration tool for Datarim (TUNE-0071).
#
# Detects non-compliance in datarim/{tasks,backlog,progress,activeContext}.md and,
# with --fix, migrates them to the thin one-liner schema:
#
#   - TASK-ID · status · P{0-3} · L{1-4} · short topic → tasks/TASK-ID-task-description.md
#
# Full description prose is externalised to datarim/tasks/{TASK-ID}-task-description.md
# with a fixed YAML frontmatter (12 keys).
#
# Default mode: dry-run (report findings, exit 1 if any). --fix applies migrations.
# Idempotent — running --fix on already-compliant tree produces no changes.
#
# Exit codes:
#   0   compliant (or --fix succeeded)
#   1   non-compliant findings (dry-run)
#   2   migration error (--fix aborted; state preserved)
#   3   concurrent invocation (lock held)
#   4   path traversal / security violation
#   64  usage error
#
# Source: PRD-TUNE-0071, plans/TUNE-0071-plan.md.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/canonicalise.sh
. "$SCRIPT_DIR/lib/canonicalise.sh"

# --- defaults ---------------------------------------------------------------
ROOT=""
MODE="dry-run"
SCOPE="all"
QUIET=0
CONFLICT_POLICY="prompt"   # TUNE-0076: prompt|keep|overwrite|skip|abort
PROBE_PREFIX=""            # TUNE-0030: --probe-prefix PREFIX → print area subdir

# --- usage ------------------------------------------------------------------
usage() {
    cat <<'EOF'
datarim-doctor.sh — index-style schema migration for datarim/

USAGE:
  datarim-doctor.sh [OPTIONS]

OPTIONS:
  --fix               Apply fixes (default: dry-run)
  --scope=<scope>     One of: tasks|backlog|active|backlog-archive|progress|descriptions|all (default: all)
  --root=<path>       Datarim root (default: walk up from $PWD)
  --quiet             Exit-code only (no stdout)
  --no-prompt         Skip conflicts in Pass 4 backlog-archive migration (alias for --conflict-policy=skip)
  --conflict-policy=<p>  One of: prompt|keep|overwrite|skip|abort (default: prompt; auto-skip in non-TTY)
  --probe-prefix=<P>  Print archive area subdir for prefix P and exit (TUNE-0030)
  --help              Print this help

EXIT CODES:
  0   compliant (or --fix succeeded)
  1   non-compliant findings (dry-run)
  2   migration error
  3   concurrent invocation (lock held)
  4   path traversal / security violation
  64  usage error
EOF
}

# --- arg parsing ------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --fix) MODE="fix" ;;
        --scope=*) SCOPE="${arg#--scope=}" ;;
        --root=*) ROOT="${arg#--root=}" ;;
        --quiet) QUIET=1 ;;
        --no-prompt) CONFLICT_POLICY="skip" ;;
        --conflict-policy=*) CONFLICT_POLICY="${arg#--conflict-policy=}" ;;
        --probe-prefix=*) PROBE_PREFIX="${arg#--probe-prefix=}" ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 64 ;;
    esac
done

# --- root resolution --------------------------------------------------------
if [ -z "$ROOT" ]; then
    cur="$PWD"
    while [ "$cur" != "/" ]; do
        if [ -d "$cur/datarim" ]; then ROOT="$cur/datarim"; break; fi
        cur="$(dirname "$cur")"
    done
fi
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
    # TUNE-0030: probe-prefix can run without datarim/ (uses $PWD walk-up only).
    if [ -n "$PROBE_PREFIX" ]; then
        ROOT_ABS="$PWD"
    else
        [ "$QUIET" -eq 0 ] && echo "ERROR: --root not specified or not a directory" >&2
        exit 64
    fi
else
    ROOT_ABS="$(cd "$ROOT" && pwd)"
fi

# --- helpers ----------------------------------------------------------------
log() { if [ "$QUIET" -eq 0 ]; then echo "$@"; fi; }
warn() { if [ "$QUIET" -eq 0 ]; then echo "WARN: $*" >&2; fi; }

# --- TUNE-0030: prefix → archive area resolution ----------------------------
# Two-tier lookup:
#   1) area prefix (universal, stack-agnostic) — defined here, owned by Datarim runtime.
#   2) project prefix — declared by caller in nearest CLAUDE.md (walk-up tree),
#      under `## Task Prefix Registry` section with table | Prefix | Project | Archive Subdir |.
# Falls back to `general` when neither matches. Path-traversal hardened.
area_prefix_to_subdir() {
    case "${1%%-*}" in
        INFRA) echo "infrastructure" ;;
        WEB) echo "web" ;;
        CONTENT) echo "content" ;;
        RESEARCH) echo "research" ;;
        AGENT) echo "agents" ;;
        BENCH) echo "benchmarks" ;;
        DEV) echo "development" ;;
        DEVOPS) echo "devops" ;;
        TUNE|ROB) echo "framework" ;;
        MAINT) echo "maintenance" ;;
        FIN) echo "finance" ;;
        QA) echo "qa" ;;
        SEC) echo "security" ;;
        *) return 1 ;;
    esac
}

lookup_project_prefix_from_claude_md() {
    local prefix="$1" start_dir="${2:-$PWD}" cwd claude_md result
    cwd="$(cd "$start_dir" 2>/dev/null && pwd)" || return 1
    [ -z "$cwd" ] && return 1
    while [ -n "$cwd" ] && [ "$cwd" != "/" ]; do
        claude_md="$cwd/CLAUDE.md"
        if [ -f "$claude_md" ]; then
            result="$(awk -v p="$prefix" '
                /^#{2,6} Task Prefix Registry/ { in_section=1; next }
                in_section && /^#{1,6} / { in_section=0 }
                in_section && /^\| *[A-Z][A-Z0-9_-]* *\|/ {
                    n = split($0, f, "|")
                    if (n < 4) next
                    pp = f[2]; gsub(/^ +| +$/, "", pp)
                    if (pp == p) {
                        sub_dir = f[4]; gsub(/^ +| +$/, "", sub_dir)
                        print sub_dir
                        exit
                    }
                }
            ' "$claude_md" 2>/dev/null)"
            if [ -n "$result" ]; then
                if [[ "$result" =~ ^[a-z][a-z0-9-]*$ ]]; then
                    echo "$result"
                    return 0
                else
                    warn "rejected unsafe Archive Subdir '$result' for prefix $prefix in $claude_md"
                    return 1
                fi
            fi
        fi
        cwd="$(dirname "$cwd")"
    done
    return 1
}

prefix_to_area() {
    local prefix="${1%%-*}" subdir
    if subdir="$(area_prefix_to_subdir "$prefix")"; then
        echo "$subdir"; return 0
    fi
    if subdir="$(lookup_project_prefix_from_claude_md "$prefix" "${ROOT_ABS:-$PWD}")"; then
        echo "$subdir"; return 0
    fi
    echo "general"
}

# Canonical regex for one-liner entries.
ONELINER_RE='^- [A-Z]{2,10}-[0-9]{4} · (in_progress|blocked|not_started|pending|blocked-pending|cancelled) · P[0-3] · L[1-4] · .{1,80} → tasks/[A-Z]{2,10}-[0-9]{4}-task-description\.md$'

validate_task_id() {
    local id="$1"
    # TUNE-0088: accept compound IDs (e.g. DEV-1212-S8, DEV-1196-FOLLOWUP-lock-ownership-doc)
    [[ "$id" =~ ^[A-Z]{2,10}-[0-9]{4}(-[A-Za-z0-9]+)*$ ]] && return 0 || return 1
}

# Validate that a description-file relpath stays inside ROOT.
validate_relpath() {
    local rel="$1" canon
    canon="$(canonicalise_path "$ROOT_ABS/$rel")"
    case "$canon" in
        "$ROOT_ABS"/*|"$ROOT_ABS") return 0 ;;
        *) return 1 ;;
    esac
}

# --- block extraction (legacy ### TASK-ID: heading) -------------------------
# Two-pass approach (bash 3.2-compatible, no NUL-delimited reads):
#   1) extract_ids <file>      → newline-separated TASK-IDs from "### ID:" headings
#   2) extract_block <file> <id> → emits the full block (heading + body) for one ID
#   3) extract_field <block> <key> → grep the "- **Key:** value" line within block
extract_ids() {
    grep -oE '^### [A-Z]+-[0-9]+:' "$1" 2>/dev/null | sed -E 's/^### //; s/:$//'
}

extract_block() {
    local file="$1" id="$2"
    awk -v id="$id" '
    BEGIN { in_block=0 }
    $0 ~ "^### " id ":" { in_block=1; print; next }
    /^### [A-Z]+-[0-9]+:|^## / && in_block { exit }
    in_block { print }
    ' "$file"
}

extract_title() {
    local file="$1" id="$2"
    grep -m1 "^### $id:" "$file" 2>/dev/null | sed -E "s/^### $id:[[:space:]]*//" || true
}

extract_field() {
    local block="$1" key="$2"
    local line
    line="$(echo "$block" | grep -m1 "^- \*\*${key}:\*\*" || true)"
    [ -z "$line" ] && return 0
    echo "$line" | sed -E "s/^- \*\*${key}:\*\*[[:space:]]*//"
}

extract_body() {
    # Body = block minus heading line minus field bullets
    local block="$1"
    echo "$block" | awk 'NR>1 && !/^- \*\*[A-Za-z]+:\*\*/ { print }'
}

norm_priority() {
    case "$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        critical|p0) echo "P0" ;;
        high|p1) echo "P1" ;;
        medium|p2) echo "P2" ;;
        low|p3) echo "P3" ;;
        *) echo "P2" ;;
    esac
}

norm_complexity() {
    local raw
    raw="$(echo "${1:-}" | sed -E 's/[Ll]evel[[:space:]]*//; s/^L//')"
    case "$raw" in
        1) echo "L1" ;;
        2) echo "L2" ;;
        3) echo "L3" ;;
        4) echo "L4" ;;
        *) echo "L2" ;;
    esac
}

norm_status() {
    case "$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        in_progress|in-progress|active) echo "in_progress" ;;
        blocked) echo "blocked" ;;
        not_started|not-started|new) echo "not_started" ;;
        pending) echo "pending" ;;
        blocked-pending|blocked_pending) echo "blocked-pending" ;;
        cancelled|canceled) echo "cancelled" ;;
        *) echo "" ;;
    esac
}

norm_topic() {
    local t="$1"
    t="${t//\*/}"
    t="${t//\`/}"
    t="$(echo "$t" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ "${#t}" -gt 80 ] && t="${t:0:77}..."
    echo "$t"
}

write_description() {
    local id="$1" title="$2" status="$3" priority="$4" complexity="$5"
    local started="$6" project="$7" body="$8"
    local out="$ROOT_ABS/tasks/$id-task-description.md"

    [ -f "$out" ] && return 0   # preserve existing

    if [ -n "$body" ]; then
        local body_lines
        body_lines="$(printf '%s' "$body" | awk 'END{print NR}')"
        if [ "${body_lines:-0}" -gt 250 ]; then
            warn "description body for $id exceeds 250 lines (got $body_lines) — emitting anyway"
        fi
    fi

    mkdir -p "$ROOT_ABS/tasks"
    {
        echo "---"
        echo "id: $id"
        echo "title: $title"
        echo "status: $status"
        echo "priority: $priority"
        echo "complexity: $complexity"
        echo "type: legacy-migrated"
        echo "project: ${project:-unknown}"
        echo "started: ${started:-2026-04-30}"
        echo "parent: null"
        echo "related: []"
        echo "prd: null"
        echo "plan: null"
        echo "---"
        echo
        echo "## Overview"
        echo
        if [ -n "$body" ]; then
            echo "$body"
        else
            echo "(migrated from legacy entry — no body extracted)"
        fi
    } > "$out"
}

# --- TUNE-0085: archive section detection -----------------------------------
# Whitelist of headers that mark archive sections in operational files. These
# sections violate the canonical thin-index contract (datarim-system.md § 49)
# and MUST be migrated to documentation/archive/{area}/archive-{ID}.md by Pass 6.
is_archive_header() {
    local line="$1"
    [[ "$line" =~ ^##[[:space:]]+Archived[[:space:]]*$ ]] && return 0
    [[ "$line" =~ ^###[[:space:]]+Archived[[:space:]]*$ ]] && return 0
    [[ "$line" =~ ^###[[:space:]]+Recently[[:space:]]+Archived[[:space:]]*$ ]] && return 0
    # TUNE-0088: Russian archive section names (operator drift in mixed-locale vaults)
    [[ "$line" =~ ^##[[:space:]]+Последние[[:space:]]+завершённые[[:space:]]*$ ]] && return 0
    [[ "$line" =~ ^###[[:space:]]+Последние[[:space:]]+завершённые[[:space:]]*$ ]] && return 0
    return 1
}

# --- compliance scan --------------------------------------------------------
FINDINGS=0
declare -a FINDING_LINES=()

scan_file() {
    local file="$1"
    [ -f "$file" ] || return 0
    local lineno=0 line
    local in_archive=0 archive_start_line=0 archive_bullets=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        # TUNE-0085: roll up archive section findings into a single entry per
        # section instead of one per bullet — distributed users see actionable
        # signal, not noise.
        if is_archive_header "$line"; then
            # Flush previous archive section finding if any (before opening new one)
            if [ "$in_archive" -eq 1 ] && [ "$archive_bullets" -gt 0 ]; then
                FINDINGS=$((FINDINGS + 1))
                FINDING_LINES+=("$file:$archive_start_line: archive section ($archive_bullets legacy entries — run --fix to migrate to documentation/archive/)")
            fi
            in_archive=1
            archive_start_line=$lineno
            archive_bullets=0
            continue
        fi
        if [ "$in_archive" -eq 1 ] && [[ "$line" =~ ^(##|###)[[:space:]] ]]; then
            # Section closed — emit rolled-up finding
            if [ "$archive_bullets" -gt 0 ]; then
                FINDINGS=$((FINDINGS + 1))
                FINDING_LINES+=("$file:$archive_start_line: archive section ($archive_bullets legacy entries — run --fix to migrate to documentation/archive/)")
            fi
            in_archive=0
            archive_bullets=0
        fi
        if [ "$in_archive" -eq 1 ]; then
            [[ "$line" =~ ^[-*][[:space:]]+\*\*[A-Z]+-[0-9]+\*\* ]] && archive_bullets=$((archive_bullets + 1))
            continue
        fi
        if [[ "$line" =~ ^###[[:space:]]+[A-Z]+-[0-9]+: ]]; then
            FINDINGS=$((FINDINGS + 1))
            FINDING_LINES+=("$file:$lineno: legacy block-style entry")
        elif [[ "$line" =~ ^[-*][[:space:]]+\*\*[A-Z]+-[0-9]+\*\* ]]; then
            FINDINGS=$((FINDINGS + 1))
            FINDING_LINES+=("$file:$lineno: legacy bold-id bullet")
        elif [[ "$line" =~ ^[-*][[:space:]]+[A-Z]+-[0-9]+ ]]; then
            if ! [[ "$line" =~ $ONELINER_RE ]]; then
                FINDINGS=$((FINDINGS + 1))
                FINDING_LINES+=("$file:$lineno: non-compliant bullet")
            fi
        fi
    done < "$file"
    # Flush trailing archive section if file ended inside one
    if [ "$in_archive" -eq 1 ] && [ "$archive_bullets" -gt 0 ]; then
        FINDINGS=$((FINDINGS + 1))
        FINDING_LINES+=("$file:$archive_start_line: archive section ($archive_bullets legacy entries — run --fix to migrate to documentation/archive/)")
    fi
}

scan_progress() {
    local file="$1"
    [ -f "$file" ] || return 0
    FINDINGS=$((FINDINGS + 1))
    FINDING_LINES+=("$file: progress.md MUST be removed (data → activeContext.md + documentation/archive/)")
}

# Validate referenced description-file paths for traversal.
scan_traversal() {
    local file="$1"
    [ -f "$file" ] || return 0
    local target line
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ →[[:space:]]+([^[:space:]]+) ]]; then
            target="${BASH_REMATCH[1]}"
            if ! validate_relpath "$target"; then
                [ "$QUIET" -eq 0 ] && echo "SECURITY: path traversal in $file: target=$target rejected" >&2
                exit 4
            fi
        fi
    done < "$file"
}

# --- TUNE-0030: probe-prefix early-exit ------------------------------------
if [ -n "$PROBE_PREFIX" ]; then
    if ! [[ "$PROBE_PREFIX" =~ ^[A-Z][A-Z0-9_-]*$ ]]; then
        [ "$QUIET" -eq 0 ] && echo "ERROR: invalid prefix '$PROBE_PREFIX' (must match ^[A-Z][A-Z0-9_-]*\$)" >&2
        exit 64
    fi
    prefix_to_area "$PROBE_PREFIX"
    exit 0
fi

scan_traversal "$ROOT_ABS/tasks.md"
scan_traversal "$ROOT_ABS/backlog.md"
scan_traversal "$ROOT_ABS/activeContext.md"

if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "tasks" ]; then
    scan_file "$ROOT_ABS/tasks.md"
fi
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "backlog" ]; then
    scan_file "$ROOT_ABS/backlog.md"
fi
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "active" ]; then
    scan_file "$ROOT_ABS/activeContext.md"
fi
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "progress" ]; then
    scan_progress "$ROOT_ABS/progress.md"
fi

# --- routing-drift advisory pass (TUNE-0022) --------------------------------
# Greps framework runtime files for canonical L1-L4 routing tokens. Surfaces
# a single rolled-up finding when any derived view (commands/skills/visual-maps)
# falls behind skills/datarim-system/routing-invariants.md. Fix is manual;
# doctor only flags. Skipped in --probe-prefix mode (already early-exited).
scan_routing_drift() {
    local script="$SCRIPT_DIR/check-routing-drift.sh"
    [ -x "$script" ] || return 0
    local rc=0
    "$script" --quiet >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ] && return 0
    if [ "$rc" -eq 1 ]; then
        local n
        n="$("$script" 2>/dev/null | grep -cE '^[a-z].*: (missing token|derived file missing)' || true)"
        FINDINGS=$((FINDINGS + 1))
        FINDING_LINES+=("routing-drift: ${n:-1} derived file(s) out of sync with skills/datarim-system/routing-invariants.md — run scripts/check-routing-drift.sh for diff")
    fi
}
if [ "$SCOPE" = "all" ]; then
    scan_routing_drift
fi

# --- dry-run ----------------------------------------------------------------
if [ "$MODE" = "dry-run" ]; then
    if [ "$FINDINGS" -eq 0 ]; then
        log "OK: datarim/ structure compliant (root=$ROOT_ABS)"
        exit 0
    fi
    log "FOUND $FINDINGS finding(s) — non-compliant. Run with --fix to migrate."
    if [ "$QUIET" -eq 0 ]; then
        for f in "${FINDING_LINES[@]}"; do echo "  $f"; done
    fi
    exit 1
fi

# --- fix mode ---------------------------------------------------------------
LOCKFILE="$ROOT_ABS/.doctor.lock"
exec 9>"$LOCKFILE" || { log "ERROR: cannot create lockfile"; exit 2; }
if command -v flock >/dev/null 2>&1; then
    if ! flock -n 9 2>/dev/null; then
        log "ERROR: another /dr-doctor is running (lock held: $LOCKFILE)"
        exit 3
    fi
fi
# Test hook: hold the lock for N seconds after acquisition to make concurrency
# races deterministic in bats. Production callers leave the var unset.
if [ -n "${DATARIM_DOCTOR_LOCK_HOLD_SECS:-}" ]; then
    sleep "$DATARIM_DOCTOR_LOCK_HOLD_SECS"
fi

# --- TUNE-0077 safety gate: pre-write backup --------------------------------
# Always tarball datarim/ before any --fix write. Restored automatically on
# invariant failure (parsed_count > emitted_count post-write).
BACKUP_DIR="${DATARIM_DOCTOR_BACKUP_DIR:-/tmp}"
BACKUP_TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_TARBALL="$BACKUP_DIR/datarim-backup-$BACKUP_TS.tgz"
mkdir -p "$BACKUP_DIR"
(
    umask 077
    tar -czf "$BACKUP_TARBALL" -C "$(dirname "$ROOT_ABS")" "$(basename "$ROOT_ABS")" 2>/dev/null
) || { log "ERROR: backup tarball failed: $BACKUP_TARBALL"; exit 2; }
[ -s "$BACKUP_TARBALL" ] || { log "ERROR: backup tarball empty: $BACKUP_TARBALL"; exit 2; }

# Capture pre-fix parsed-block count (single source of truth for invariant)
PARSED_COUNT=0
for f in "$ROOT_ABS/tasks.md" "$ROOT_ABS/backlog.md"; do
    [ -f "$f" ] || continue
    n=$(grep -cE '^### [A-Z]+-[0-9]+:' "$f" 2>/dev/null || true)
    PARSED_COUNT=$((PARSED_COUNT + n))
done
if [ -f "$ROOT_ABS/activeContext.md" ]; then
    # TUNE-0073: count only rich-block entries that migrate_active_context consumes
    # (`- **ID** (status, date) — title` shape). Excludes ✅-bullets in
    # «Последние завершённые», which Gate v2-B already strips.
    n_active=$(grep -cE '^- \*\*[A-Z]+-[0-9]+\*\* \(' "$ROOT_ABS/activeContext.md" 2>/dev/null || true)
    PARSED_COUNT=$((PARSED_COUNT + n_active))
fi

# Restore-and-die helper for invariant failure
restore_backup_and_die() {
    local reason="$1"
    log "INVARIANT VIOLATION: $reason — restoring from $BACKUP_TARBALL"
    rm -rf "$ROOT_ABS"
    tar -xzf "$BACKUP_TARBALL" -C "$(dirname "$ROOT_ABS")" 2>/dev/null \
        || { log "ERROR: restore from $BACKUP_TARBALL failed — manual recovery required"; exit 2; }
    exit 2
}

migrate_file() {
    local src="$1" out="$2" heading="$3" status_default="$4"
    [ -f "$src" ] || return 0
    # Idempotency: if file has zero legacy headings, treat as already compliant.
    if ! grep -qE '^### [A-Z]+-[0-9]+:' "$src"; then
        return 0
    fi
    local -a out_lines=()
    local id title block status priority complexity started project topic body

    while IFS= read -r id; do
        [ -z "$id" ] && continue
        validate_task_id "$id" || { warn "skip invalid id: $id"; continue; }
        title="$(extract_title "$src" "$id")"
        block="$(extract_block "$src" "$id")"

        status="$(norm_status "$(extract_field "$block" "Status")")"
        [ -z "$status" ] && status="$status_default"
        priority="$(norm_priority "$(extract_field "$block" "Priority")")"
        complexity="$(norm_complexity "$(extract_field "$block" "Complexity")")"
        started="$(extract_field "$block" "Started")"
        [ -z "$started" ] && started="$(extract_field "$block" "Added")"
        project="$(extract_field "$block" "Project")"
        body="$(extract_body "$block")"
        topic="$(norm_topic "$title")"

        write_description "$id" "$topic" "$status" "$priority" "$complexity" \
                          "$started" "$project" "$body"

        out_lines+=("- $id · $status · $priority · $complexity · $topic → tasks/$id-task-description.md")
    done < <(extract_ids "$src")

    if [ "${#out_lines[@]}" -gt 0 ]; then
        local sorted
        sorted="$(printf '%s\n' "${out_lines[@]}" | sort -u)"
        printf '%s\n\n%s\n' "$heading" "$sorted" > "$out"
    else
        printf '%s\n\n<!-- no entries -->\n' "$heading" > "$out"
    fi
}

# TUNE-0030: prefix_to_area moved earlier (before probe-prefix early-exit). See top of file.

resolve_conflict() {
    # TUNE-0076: returns 0 if caller should overwrite, 1 if skip, exits 2 on abort
    local id="$1" target="$2" new_content="$3"
    local policy="$CONFLICT_POLICY"
    if [ "$policy" = "prompt" ] && ! [ -t 0 ] && [ -z "${DATARIM_DOCTOR_TTY_OVERRIDE:-}" ]; then policy="skip"; fi
    case "$policy" in
        keep|skip) return 1 ;;
        overwrite) return 0 ;;
        abort) log "ABORT: conflict on $id"; exit 2 ;;
        prompt)
            diff -u "$target" <(printf '%s\n' "$new_content") 2>&1 | head -40 >&2 || true
            printf 'Conflict on %s — [k]eep [o]verwrite [s]kip [a]bort: ' "$id" >&2
            local choice; read -r choice
            case "${choice:-s}" in
                o|O) return 0 ;;
                a|A) exit 2 ;;
                *) return 1 ;;
            esac
            ;;
        *) warn "unknown conflict policy: $policy → skip"; return 1 ;;
    esac
}

synthesise_cancelled_archive() {
    local id="$1" title="$2" block="$3"
    local cancelled_at; cancelled_at="$(extract_field "$block" "Cancelled")"
    local reason; reason="$(extract_field "$block" "Reason")"
    local body; body="$(extract_body "$block")"
    local sha; sha="$(printf '%s' "$block" | shasum 2>/dev/null | awk '{print substr($1,1,7)}')"
    local target="$DOCS_ARCHIVE_ROOT/cancelled/archive-$id.md"
    local content
    content="$(cat <<EOF
---
id: $id
title: $title
status: cancelled
cancelled_at: ${cancelled_at:-unknown}
reason: ${reason:-not specified}
source: synthesised from backlog-archive.md by datarim-doctor.sh Pass 4 (TUNE-0076)
original_block_sha: $sha
---

## Overview

$body
EOF
)"
    if [ -f "$target" ]; then
        if grep -q "$id" "$target"; then return 0; fi   # verified, no rewrite
        if ! resolve_conflict "$id" "$target" "$content"; then return 1; fi
    fi
    mkdir -p "$(dirname "$target")"
    printf '%s\n' "$content" > "$target"
}

synthesise_completed_archive() {
    local id="$1" title="$2" block="$3" area="$4"
    local completed_at; completed_at="$(extract_field "$block" "Completed")"
    local body; body="$(extract_body "$block")"
    local sha; sha="$(printf '%s' "$block" | shasum 2>/dev/null | awk '{print substr($1,1,7)}')"
    local target="$DOCS_ARCHIVE_ROOT/$area/archive-$id.md"
    local content
    content="$(cat <<EOF
---
id: $id
title: $title
status: completed
completed_at: ${completed_at:-unknown}
source: synthesised from backlog-archive.md by datarim-doctor.sh Pass 4 (TUNE-0076)
original_block_sha: $sha
---

## Overview

$body
EOF
)"
    if [ -f "$target" ]; then
        if grep -q "$id" "$target"; then return 0; fi   # verified existing
        if ! resolve_conflict "$id" "$target" "$content"; then return 1; fi
    fi
    mkdir -p "$(dirname "$target")"
    printf '%s\n' "$content" > "$target"
}

migrate_backlog_archive() {
    # TUNE-0076: Pass 4 — migrate backlog-archive.md → documentation/archive/{area}/
    local src="$ROOT_ABS/backlog-archive.md"
    [ -f "$src" ] || return 0

    DOCS_ARCHIVE_ROOT="$(dirname "$ROOT_ABS")/documentation/archive"
    cp "$src" "$src.pre-v2.bak"

    local TMP_SECMAP
    TMP_SECMAP="$(mktemp -t doctor-secmap.XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -f '$TMP_SECMAP'" EXIT INT TERM

    awk '
        /^## Cancelled$/ { sec="cancelled"; next }
        /^## Completed$/ { sec="completed"; next }
        /^### [A-Z]+-[0-9]+:/ {
            id = $2; sub(/:$/, "", id)
            if (sec != "" && id ~ /^[A-Z]+-[0-9]+$/) print sec "\t" id
        }
    ' "$src" > "$TMP_SECMAP"

    local sec id title block area parsed=0
    while IFS=$'\t' read -r sec id; do
        validate_task_id "$id" || continue
        title="$(extract_title "$src" "$id")"
        block="$(extract_block "$src" "$id")"
        parsed=$((parsed + 1))
        if [ "$sec" = "cancelled" ]; then
            synthesise_cancelled_archive "$id" "$title" "$block" || true
        else
            area="$(prefix_to_area "$id")"
            local existing="$DOCS_ARCHIVE_ROOT/$area/archive-$id.md"
            if [ -f "$existing" ] && grep -q "$id" "$existing"; then
                continue   # verified existing, no synthesis
            fi
            synthesise_completed_archive "$id" "$title" "$block" "general" || true
        fi
    done < "$TMP_SECMAP"

    log "Pass 4: migrated $parsed entries from backlog-archive.md → documentation/archive/"
    rm -f "$src"
}

migrate_active_context() {
    # TUNE-0073: rich-block bullet → thin one-liner for activeContext.md
    local src="$ROOT_ABS/activeContext.md"
    [ -f "$src" ] || return 0
    grep -qE '^- \*\*[A-Z]+-[0-9]+\*\*' "$src" || return 0   # idempotent

    local -a out=()
    local id status started title comp prio rest line lookup
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^-\ \*\*([A-Z]+-[0-9]+)\*\*\ \(([a-z_]+),\ ([0-9-]+)\)\ —\ (.+)$ ]]; then
            id="${BASH_REMATCH[1]}"; status="${BASH_REMATCH[2]}"
            started="${BASH_REMATCH[3]}"; rest="${BASH_REMATCH[4]}"
            validate_task_id "$id" || continue
            # Strip trailing dot
            rest="${rest%.}"
            # Try inline "(Level N, PN)" suffix
            if [[ "$rest" =~ ^(.+)\ \(Level\ ([1-4]),\ (P[0-3])\)$ ]]; then
                title="${BASH_REMATCH[1]}"
                comp="L${BASH_REMATCH[2]}"
                prio="${BASH_REMATCH[3]}"
            else
                title="$rest"
                # Cross-lookup tasks.md thin-index
                lookup=""
                [ -f "$ROOT_ABS/tasks.md" ] && \
                    lookup="$(grep -m1 "^- $id · " "$ROOT_ABS/tasks.md" 2>/dev/null || true)"
                if [ -n "$lookup" ]; then
                    prio="$(echo "$lookup" | awk -F' · ' '{print $3}')"
                    comp="$(echo "$lookup" | awk -F' · ' '{print $4}')"
                else
                    prio="P2"; comp="L2"
                fi
            fi
            title="$(norm_topic "$title")"
            out+=("- $id · $status · $prio · $comp · $title → tasks/$id-task-description.md")
        fi
    done < "$src"

    if [ "${#out[@]}" -gt 0 ]; then
        local sorted
        sorted="$(printf '%s\n' "${out[@]}" | sort -u)"
        printf '# Active Context\n\n## Active Tasks\n\n%s\n' "$sorted" > "$src"
    fi
}

# --- TUNE-0085: Pass 6 — operational-files archive section migration --------
# Strip ## Archived / ### Recently Archived / ### Archived sections from
# operational files; for each archive bullet, verify or synthesise a canonical
# archive doc at documentation/archive/{area}/archive-{ID}.md, then drop the
# bullet. Collisions (existing archive doc without {ID} literal) preserve the
# bullet in operational file with a manual-migration marker.

# Parse one of 3 known archive-bullet shapes. Outputs TSV:
#   id<TAB>title<TAB>date<TAB>status_hint<TAB>body
# Returns 0 on parse success, 1 on unparseable.
parse_archive_bullet() {
    local line="$1"
    local id title date status_hint body context
    # TUNE-0088: ID may be compound — DEV-1226, DEV-1212-S8, DEV-1196-FOLLOWUP-lock-ownership-doc.
    # Numeric component required (excludes false positives like **TODO**, **SECTION-1**).
    # S1: - **ID** — title (YYYY-MM-DD) → path
    if [[ "$line" =~ ^-[[:space:]]+\*\*([A-Z]+-[0-9]+(-[A-Za-z0-9]+)*)\*\*[[:space:]]+—[[:space:]]+(.+)[[:space:]]+\(([0-9]{4}-[0-9]{2}-[0-9]{2})\)[[:space:]]+→[[:space:]]+ ]]; then
        id="${BASH_REMATCH[1]}"
        title="${BASH_REMATCH[3]}"
        date="${BASH_REMATCH[4]}"
        status_hint="completed"
        body="$line"
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$title" "$date" "$status_hint" "$body"
        return 0
    fi
    # S2: - **ID** (status, YYYY-MM-DD) — title
    if [[ "$line" =~ ^-[[:space:]]+\*\*([A-Z]+-[0-9]+(-[A-Za-z0-9]+)*)\*\*[[:space:]]+\(([a-z_]+),[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2})\)[[:space:]]+—[[:space:]]+(.+)$ ]]; then
        id="${BASH_REMATCH[1]}"
        status_hint="${BASH_REMATCH[3]}"
        date="${BASH_REMATCH[4]}"
        title="${BASH_REMATCH[5]}"
        title="${title%.}"
        body="$line"
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$title" "$date" "$status_hint" "$body"
        return 0
    fi
    # S4 (TUNE-0088): - **ID** context-words — title  (mid-bold context phrase)
    # More specific than S3, tested before it.
    if [[ "$line" =~ ^-[[:space:]]+\*\*([A-Z]+-[0-9]+(-[A-Za-z0-9]+)*)\*\*[[:space:]]+([^—]+)[[:space:]]+—[[:space:]]+(.+)$ ]]; then
        id="${BASH_REMATCH[1]}"
        context="${BASH_REMATCH[3]}"
        context="${context%[[:space:]]}"
        title="${BASH_REMATCH[4]} (context: ${context})"
        date=""
        status_hint="completed"
        body="$line"
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$title" "$date" "$status_hint" "$body"
        return 0
    fi
    # S3: - **ID** — title (no date, no link)
    if [[ "$line" =~ ^-[[:space:]]+\*\*([A-Z]+-[0-9]+(-[A-Za-z0-9]+)*)\*\*[[:space:]]+—[[:space:]]+(.+)$ ]]; then
        id="${BASH_REMATCH[1]}"
        title="${BASH_REMATCH[3]}"
        date=""
        status_hint="completed"
        body="$line"
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$title" "$date" "$status_hint" "$body"
        return 0
    fi
    return 1
}

# Synthesise minimal canonical archive stub from inline bullet.
# args: id title date status_hint body target_path
synthesise_archive_stub() {
    local id="$1" title="$2" date="$3" status_hint="$4" body="$5" target="$6"
    local status="completed"
    [ "$status_hint" = "cancelled" ] && status="cancelled"
    local sha; sha="$(printf '%s' "$body" | shasum 2>/dev/null | awk '{print substr($1,1,7)}')"
    local date_field="${status}_at"
    mkdir -p "$(dirname "$target")"
    {
        echo "---"
        echo "id: $id"
        echo "title: $title"
        echo "status: $status"
        echo "${date_field}: ${date:-unknown}"
        echo "source: synthesised from operational-file by datarim-doctor.sh Pass 6 (TUNE-0085)"
        echo "original_block_sha: $sha"
        echo "---"
        echo
        echo "## Overview"
        echo
        echo "$body"
    } > "$target"
}

# TUNE-0088 Bug 3: headerless fallback — operational file without ### Recently Archived header.
# Per-line scan: parseable archive bullets handled, others passed through unchanged.
migrate_headerless_archive() {
    local src="$1"
    local docs_root
    docs_root="$(dirname "$ROOT_ABS")/documentation/archive"
    local active_part="" preserve_bullets=""
    local parsed=0 stripped=0 synthesised=0 skipped=0
    local line parsed_tsv id title date status_hint body area canonical_path explicit_path found_path

    while IFS= read -r line || [ -n "$line" ]; do
        if parsed_tsv="$(parse_archive_bullet "$line")"; then
            IFS=$'\t' read -r id title date status_hint body <<< "$parsed_tsv"
            if ! validate_task_id "$id"; then
                # Not a real task ID — pass through as active content
                active_part+="$line"$'\n'
                continue
            fi
            # TUNE-0088: in headerless mode, skip bullets with explicit non-terminal status —
            # they're active, not archive (defends against rewriting `## Active Tasks` legacy block).
            case "$status_hint" in
                in_progress|not_started|pending|blocked|approved|review|active)
                    active_part+="$line"$'\n'
                    continue
                    ;;
            esac
            parsed=$((parsed + 1))
            # Explicit-pointer dispatch (same logic as migrate_operational_archive)
            explicit_path=""
            if [[ "$body" =~ →[[:space:]]+(documentation/archive/[A-Za-z0-9_/.-]+\.md)([[:space:]]|$) ]]; then
                explicit_path="${BASH_REMATCH[1]}"
            fi
            if [ -n "$explicit_path" ]; then
                canonical_path="$(dirname "$ROOT_ABS")/$explicit_path"
            else
                area="$(prefix_to_area "$id")"
                canonical_path="$docs_root/$area/archive-$id.md"
            fi
            case "$canonical_path" in
                "$docs_root"/*) ;;
                *) warn "Pass 6 (headerless): rejected path outside archive root: $canonical_path"
                   if [ -n "$explicit_path" ]; then
                       area="$(prefix_to_area "$id")"
                       canonical_path="$docs_root/$area/archive-$id.md"
                       case "$canonical_path" in
                           "$docs_root"/*) ;;
                           *) preserve_bullets+="$line"$'\n'; continue ;;
                       esac
                   else
                       preserve_bullets+="$line"$'\n'; continue
                   fi
                   ;;
            esac
            if [ -f "$canonical_path" ] && grep -q "$id" "$canonical_path"; then
                stripped=$((stripped + 1))
            else
                # Defensive find — canonical may live under unexpected area subdir
                found_path="$(find "$docs_root" -maxdepth 3 -type f -name "archive-${id}.md" -print -quit 2>/dev/null)"
                if [ -n "$found_path" ] && grep -q "$id" "$found_path"; then
                    warn "Pass 6 (headerless): archive at unexpected area: $found_path"
                    stripped=$((stripped + 1))
                else
                    synthesise_archive_stub "$id" "$title" "$date" "$status_hint" "$body" "$canonical_path"
                    synthesised=$((synthesised + 1))
                fi
            fi
        else
            active_part+="$line"$'\n'
        fi
    done < "$src"

    # If nothing parsed, do not touch the file (idempotency)
    if [ "$parsed" -eq 0 ]; then
        return 0
    fi

    active_part="${active_part%$'\n'}"
    if [ -n "$preserve_bullets" ]; then
        preserve_bullets="${preserve_bullets%$'\n'}"
        printf '%s\n\n<!-- TUNE-0088: headerless bullets pending manual migration -->\n%s\n' \
            "$active_part" "$preserve_bullets" > "$src"
    else
        printf '%s\n' "$active_part" > "$src"
    fi
    log "Pass 6 ${src##*/} (headerless): parsed=$parsed stripped=$stripped synthesised=$synthesised skipped=$skipped"
    PASS6_PARSED_TOTAL=$((${PASS6_PARSED_TOTAL:-0} + parsed))
    PASS6_EMITTED_TOTAL=$((${PASS6_EMITTED_TOTAL:-0} + stripped + synthesised + skipped))
}

# Pass 6 entry point per file. Detects archive section, processes each bullet,
# rewrites file with active section only (+ preserved orphan bullets if any).
migrate_operational_archive() {
    local src="$1"
    [ -f "$src" ] || return 0
    # Idempotent: skip files without any archive header
    local has_archive=0
    while IFS= read -r line || [ -n "$line" ]; do
        if is_archive_header "$line"; then has_archive=1; break; fi
    done < "$src"
    if [ "$has_archive" -eq 0 ]; then
        # TUNE-0088 Bug 3: headerless legacy bullets — operator drift, scanner finds them but
        # Pass 6 used to early-return. Option A: fall back to per-line scan.
        migrate_headerless_archive "$src"
        return $?
    fi

    local docs_root
    docs_root="$(dirname "$ROOT_ABS")/documentation/archive"
    local active_part="" preserve_bullets=""
    local in_archive=0
    local parsed=0 stripped=0 synthesised=0 skipped=0
    local line parsed_tsv id title date status_hint body area canonical_path explicit_path found_path

    while IFS= read -r line || [ -n "$line" ]; do
        if is_archive_header "$line"; then
            in_archive=1
            continue
        fi
        if [ "$in_archive" -eq 1 ] && [[ "$line" =~ ^(##|###)[[:space:]] ]]; then
            in_archive=0
            active_part+="$line"$'\n'
            continue
        fi
        if [ "$in_archive" -eq 0 ]; then
            active_part+="$line"$'\n'
            continue
        fi
        # Inside archive section
        # Skip blank lines and HTML comments (not bullets)
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*\<\!--.*--\>[[:space:]]*$ ]]; then
            continue
        fi
        # Try parse as archive bullet
        if parsed_tsv="$(parse_archive_bullet "$line")"; then
            parsed=$((parsed + 1))
            IFS=$'\t' read -r id title date status_hint body <<< "$parsed_tsv"
            validate_task_id "$id" || {
                warn "Pass 6: invalid task id in archive bullet: $line"
                preserve_bullets+="$line"$'\n'
                continue
            }
            # TUNE-0088 Bug 1: prefer explicit pointer (→ documentation/archive/...) over prefix_to_area
            explicit_path=""
            if [[ "$body" =~ →[[:space:]]+(documentation/archive/[A-Za-z0-9_/.-]+\.md)([[:space:]]|$) ]]; then
                explicit_path="${BASH_REMATCH[1]}"
            fi
            if [ -n "$explicit_path" ]; then
                canonical_path="$(dirname "$ROOT_ABS")/$explicit_path"
            else
                area="$(prefix_to_area "$id")"
                canonical_path="$docs_root/$area/archive-$id.md"
            fi
            # Path-traversal safety: canonical_path must stay under docs_root
            case "$canonical_path" in
                "$docs_root"/*) ;;
                *) warn "Pass 6: rejected canonical path outside archive root: $canonical_path"
                   # Fall back to prefix_to_area when explicit pointer rejected
                   if [ -n "$explicit_path" ]; then
                       area="$(prefix_to_area "$id")"
                       canonical_path="$docs_root/$area/archive-$id.md"
                       case "$canonical_path" in
                           "$docs_root"/*) ;;
                           *) preserve_bullets+="$line"$'\n'; continue ;;
                       esac
                   else
                       preserve_bullets+="$line"$'\n'; continue
                   fi
                   ;;
            esac
            if [ -f "$canonical_path" ]; then
                if grep -q "$id" "$canonical_path"; then
                    # Verified: archive doc has ID literal — strip bullet
                    stripped=$((stripped + 1))
                else
                    # Collision: existing archive doc without ID literal
                    if resolve_conflict "$id" "$canonical_path" ""; then
                        synthesise_archive_stub "$id" "$title" "$date" "$status_hint" "$body" "$canonical_path"
                        synthesised=$((synthesised + 1))
                    else
                        skipped=$((skipped + 1))
                        preserve_bullets+="$line"$'\n'
                    fi
                fi
            else
                # TUNE-0088 Bug 4: defensive find — canonical may live under unexpected area subdir
                found_path="$(find "$docs_root" -maxdepth 3 -type f -name "archive-${id}.md" -print -quit 2>/dev/null)"
                if [ -n "$found_path" ] && grep -q "$id" "$found_path"; then
                    warn "Pass 6: archive at unexpected area: $found_path (computed: $canonical_path)"
                    stripped=$((stripped + 1))
                else
                    # Missing: synthesise stub
                    synthesise_archive_stub "$id" "$title" "$date" "$status_hint" "$body" "$canonical_path"
                    synthesised=$((synthesised + 1))
                fi
            fi
        else
            warn "Pass 6: unparseable archive bullet in $src: $line"
            preserve_bullets+="$line"$'\n'
        fi
    done < "$src"

    # Rewrite file: active part + (preserved orphan bullets with marker if any)
    # Strip trailing blank lines from active_part for clean output
    active_part="${active_part%$'\n'}"
    if [ -n "$preserve_bullets" ]; then
        preserve_bullets="${preserve_bullets%$'\n'}"
        printf '%s\n\n<!-- TUNE-0085: bullets pending manual migration — fix conflict in documentation/archive/, then re-run /dr-doctor --fix -->\n%s\n' \
            "$active_part" "$preserve_bullets" > "$src"
    else
        printf '%s\n' "$active_part" > "$src"
    fi

    log "Pass 6 ${src##*/}: parsed=$parsed stripped=$stripped synthesised=$synthesised skipped=$skipped"
    PASS6_PARSED_TOTAL=$((${PASS6_PARSED_TOTAL:-0} + parsed))
    PASS6_EMITTED_TOTAL=$((${PASS6_EMITTED_TOTAL:-0} + stripped + synthesised + skipped))
}

PASS6_PARSED_TOTAL=0
PASS6_EMITTED_TOTAL=0
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "tasks" ]; then
    migrate_operational_archive "$ROOT_ABS/tasks.md"
fi
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "backlog" ]; then
    migrate_operational_archive "$ROOT_ABS/backlog.md"
fi
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "active" ]; then
    migrate_operational_archive "$ROOT_ABS/activeContext.md"
fi

if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "tasks" ]; then
    migrate_file "$ROOT_ABS/tasks.md" "$ROOT_ABS/tasks.md" "# Tasks"$'\n\n''## Active' "in_progress"
fi
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "backlog" ]; then
    migrate_file "$ROOT_ABS/backlog.md" "$ROOT_ABS/backlog.md" "# Backlog"$'\n\n''## Pending' "pending"
fi
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "active" ]; then
    migrate_active_context
fi
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "backlog-archive" ]; then
    migrate_backlog_archive
fi

if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "progress" ]; then
    if [ -f "$ROOT_ABS/progress.md" ]; then
        rm -f "$ROOT_ABS/progress.md"
        log "DELETED $ROOT_ABS/progress.md (data preserved in documentation/archive/)"
    fi
fi

# --- TUNE-0077 safety gate: post-write invariant check ----------------------
# After all writes, count emitted one-liners. Must be >= parsed blocks (no data
# loss). Mismatch → restore from backup tarball and exit 2.
EMITTED_COUNT=0
for f in "$ROOT_ABS/tasks.md" "$ROOT_ABS/backlog.md" "$ROOT_ABS/activeContext.md"; do
    [ -f "$f" ] || continue
    n=$(grep -cE '^- [A-Z]+-[0-9]+ · ' "$f" 2>/dev/null || true)
    EMITTED_COUNT=$((EMITTED_COUNT + n))
done

if [ "$EMITTED_COUNT" -lt "$PARSED_COUNT" ]; then
    restore_backup_and_die "emitted=$EMITTED_COUNT < parsed=$PARSED_COUNT (data loss detected)"
fi

command -v flock >/dev/null 2>&1 && flock -u 9 2>/dev/null || true
log "OK: migration complete (root=$ROOT_ABS, parsed=$PARSED_COUNT, emitted=$EMITTED_COUNT)"
log "Backup: $BACKUP_TARBALL"
exit 0
