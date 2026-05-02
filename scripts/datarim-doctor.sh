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

# --- usage ------------------------------------------------------------------
usage() {
    cat <<'EOF'
datarim-doctor.sh — index-style schema migration for datarim/

USAGE:
  datarim-doctor.sh [OPTIONS]

OPTIONS:
  --fix               Apply fixes (default: dry-run)
  --scope=<scope>     One of: tasks|backlog|active|progress|descriptions|all (default: all)
  --root=<path>       Datarim root (default: walk up from $PWD)
  --quiet             Exit-code only (no stdout)
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
    [ "$QUIET" -eq 0 ] && echo "ERROR: --root not specified or not a directory" >&2
    exit 64
fi
ROOT_ABS="$(cd "$ROOT" && pwd)"

# --- helpers ----------------------------------------------------------------
log() { if [ "$QUIET" -eq 0 ]; then echo "$@"; fi; }
warn() { if [ "$QUIET" -eq 0 ]; then echo "WARN: $*" >&2; fi; }

# Canonical regex for one-liner entries.
ONELINER_RE='^- [A-Z]{2,10}-[0-9]{4} · (in_progress|blocked|not_started|pending|blocked-pending|cancelled) · P[0-3] · L[1-4] · .{1,80} → tasks/[A-Z]{2,10}-[0-9]{4}-task-description\.md$'

validate_task_id() {
    local id="$1"
    [[ "$id" =~ ^[A-Z]{2,10}-[0-9]{4}$ ]] && return 0 || return 1
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

# --- compliance scan --------------------------------------------------------
FINDINGS=0
declare -a FINDING_LINES=()

scan_file() {
    local file="$1"
    [ -f "$file" ] || return 0
    local lineno=0 line
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
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

scan_traversal "$ROOT_ABS/tasks.md"
scan_traversal "$ROOT_ABS/backlog.md"
scan_traversal "$ROOT_ABS/activeContext.md"

if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "tasks" ]; then
    scan_file "$ROOT_ABS/tasks.md"
fi
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "backlog" ]; then
    scan_file "$ROOT_ABS/backlog.md"
fi
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "progress" ]; then
    scan_progress "$ROOT_ABS/progress.md"
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

if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "tasks" ]; then
    migrate_file "$ROOT_ABS/tasks.md" "$ROOT_ABS/tasks.md" "# Tasks"$'\n\n''## Active' "in_progress"
fi
if [ "$SCOPE" = "all" ] || [ "$SCOPE" = "backlog" ]; then
    migrate_file "$ROOT_ABS/backlog.md" "$ROOT_ABS/backlog.md" "# Backlog"$'\n\n''## Pending' "pending"
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
for f in "$ROOT_ABS/tasks.md" "$ROOT_ABS/backlog.md"; do
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
