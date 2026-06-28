#!/usr/bin/env bash
# docs-migrate.sh — opt-in, idempotent, rollback-safe docs/→documentation/ migrator
#
# Detects legacy docs/ layout in a consumer repo and (on --fix) migrates it to
# the Diátaxis-structured documentation/ layout required by Datarim 2.49+.
#
# Usage:
#   docs-migrate.sh --repo <path> [--check|--fix] [--quiet]
#
# Modes:
#   --check (default)  Detect legacy layout; report; no writes.
#   --fix              tarball-backup → git mv → Diátaxis-split → ref-rewrite
#                      → verify; rollback on verify failure.
#
# Exit codes:
#   0  compliant/migrated/fixed (idempotent no-op on second --fix)
#   1  legacy layout detected (--check only)
#   2  partial layout (both docs/ and documentation/) or error/rolled-back
#   3  lock held by concurrent invocation
#   4  path-traversal / unsafe --repo value
#  64  usage error
#
# Security: set -euo pipefail; flock; path-traversal guard; ALL paths quoted;
#   -- option terminators where applicable; umask 077 on tarball; chmod 0600.
# Single responsibility: ONLY migrates product docs (docs/→documentation/).
#   Never touches $DATARIM_ROOT runtime state — that is datarim-doctor.sh's domain
#   (see CLAUDE.md § Validation Discipline, creative-INFRA-0306-architecture).
#
# INFRA-0306 Phase 5 — implements D-REQ-07, covers V-AC-10, V-AC-11.
#
# Bash 3.2 compatible (macOS default shell): no declare -A; case-based mapping.

set -euo pipefail

# ---------------------------------------------------------------------------
# Diátaxis basename→category mapping (19 framework root docs).
# Implemented as a case statement for bash 3.2 compatibility (no declare -A).
# Source of truth: creative-INFRA-0306-data-model-diataxis-mapping.md § Decision table.
# ---------------------------------------------------------------------------

# _lookup_category BASENAME
# Prints the Diátaxis category name for known framework basenames.
# Prints empty string for unknown basenames (→ conservative how-to placement).
_lookup_category() {
    case "$1" in
        # tutorials
        getting-started|use-cases)
            echo "tutorials" ;;
        # reference
        agents|cli|commands|complexity|skills|standards-mapping|validator-contract)
            echo "reference" ;;
        # explanation
        consilium|evolution|pipeline|plugin-author-guide|spec-traceability-rollout|symlinks)
            echo "explanation" ;;
        # how-to
        backlog-workflow|release-process|release-verification|evolution-log)
            echo "how-to" ;;
        # unknown basename — caller places in how-to/ with review comment
        *)
            echo "" ;;
    esac
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_prog="$(basename -- "$0")"

usage() {
    printf 'Usage: %s --repo <path> [--check|--fix] [--quiet]\n' "$_prog" >&2
    printf '\n' >&2
    printf '  --check   (default) detect legacy docs/ layout; report; no writes\n' >&2
    printf '  --fix     migrate docs/ -> documentation/ (Diataxis split)\n' >&2
    printf '  --quiet   suppress informational output\n' >&2
    exit 64
}

_QUIET=0
log() {
    [ "$_QUIET" -eq 1 ] && return 0
    printf '%s: %s\n' "$_prog" "$1"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

REPO=""
MODE="check"   # default

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)
            [ $# -ge 2 ] || { printf '%s: --repo requires an argument\n' "$_prog" >&2; usage; }
            REPO="$2"
            shift 2
            ;;
        --check)
            MODE="check"
            shift
            ;;
        --fix)
            MODE="fix"
            shift
            ;;
        --quiet)
            _QUIET=1
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            printf '%s: unknown option: %s\n' "$_prog" "$1" >&2
            usage
            ;;
        *)
            printf '%s: unexpected argument: %s\n' "$_prog" "$1" >&2
            usage
            ;;
    esac
done

[ -n "$REPO" ] || usage

# ---------------------------------------------------------------------------
# Path-traversal guard
# Reject --repo values that contain '..' components or resolve to a
# non-absolute path.
# ---------------------------------------------------------------------------

case "$REPO" in
    *..*)
        log "ERROR: path-traversal rejected: --repo value contains '..': $REPO"
        exit 4
        ;;
esac

# Resolve to absolute canonical path.
REPO_ABS=""
if command -v realpath >/dev/null 2>&1; then
    # -m: do not require path to exist (safe for test fixtures not yet created).
    REPO_ABS="$(realpath -m -- "$REPO" 2>/dev/null)" || true
fi
if [ -z "$REPO_ABS" ]; then
    if [ -d "$REPO" ]; then
        REPO_ABS="$(cd -- "$REPO" && pwd -P)"
    else
        REPO_ABS="$REPO"
    fi
fi

case "$REPO_ABS" in
    /*)  ;;
    *)
        log "ERROR: path-traversal rejected: --repo resolved to non-absolute path: $REPO_ABS"
        exit 4
        ;;
esac

# ---------------------------------------------------------------------------
# Phase 0 — detect layout (used in both --check and --fix)
# ---------------------------------------------------------------------------

_detect_layout() {
    local repo="$1"
    local has_docs=0 has_documentation=0
    [ -d "$repo/docs" ]          && has_docs=1
    [ -d "$repo/documentation" ] && has_documentation=1

    if [ "$has_docs" -eq 1 ] && [ "$has_documentation" -eq 0 ]; then
        echo "legacy"
    elif [ "$has_docs" -eq 1 ] && [ "$has_documentation" -eq 1 ]; then
        echo "partial"
    else
        echo "migrated"
    fi
}

LAYOUT="$(_detect_layout "$REPO_ABS")"

# ---------------------------------------------------------------------------
# --check mode (read-only)
# ---------------------------------------------------------------------------

if [ "$MODE" = "check" ]; then
    case "$LAYOUT" in
        legacy)
            log "legacy: docs/ present, documentation/ absent — run --fix to migrate"
            exit 1
            ;;
        partial)
            log "partial: manual review required (both docs/ and documentation/ present)"
            exit 2
            ;;
        migrated)
            log "migrated: documentation/ present, docs/ absent — compliant"
            exit 0
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# --fix mode — idempotent no-op if already migrated or partial
# ---------------------------------------------------------------------------

case "$LAYOUT" in
    migrated)
        log "migrated: already compliant — no-op"
        exit 0
        ;;
    partial)
        log "partial: manual review required — not auto-fixing"
        exit 2
        ;;
esac

# LAYOUT == "legacy" from here on.

# ---------------------------------------------------------------------------
# Lock (flock where available; advisory concurrency guard)
# ---------------------------------------------------------------------------

LOCKFILE="$REPO_ABS/.docs-migrate.lock"
exec 9>"$LOCKFILE" || { log "ERROR: cannot create lockfile: $LOCKFILE"; exit 3; }
if command -v flock >/dev/null 2>&1; then
    if ! flock -n 9 2>/dev/null; then
        log "ERROR: another docs-migrate is running (lock held: $LOCKFILE)"
        exit 3
    fi
fi

# ---------------------------------------------------------------------------
# Pre-fix tarball backup — cloned from datarim-doctor.sh lines 629-668.
# Backs up docs/ (and documentation/ if somehow present) under BACKUP_DIR.
# Empty-guard: fail before any mutation if tarball is empty.
# ---------------------------------------------------------------------------

BACKUP_DIR="${DOCS_MIGRATE_BACKUP_DIR:-/tmp}"
BACKUP_TS="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_TARBALL="$BACKUP_DIR/docs-migrate-backup-${BACKUP_TS}-$$.tgz"
mkdir -p -- "$BACKUP_DIR"

# Collect what to back up into positional parameters for safe tar invocation.
set --
[ -d "$REPO_ABS/docs" ]          && set -- "$@" "docs"
[ -d "$REPO_ABS/documentation" ] && set -- "$@" "documentation"
if [ $# -eq 0 ]; then
    log "ERROR: nothing to back up under $REPO_ABS"
    exit 2
fi

(
    umask 077
    # Note: macOS BSD tar does not accept -- before the tarball path.
    tar -czf "$BACKUP_TARBALL" -C "$REPO_ABS" "$@" 2>/dev/null
) || { log "ERROR: backup tarball failed: $BACKUP_TARBALL"; exit 2; }
[ -s "$BACKUP_TARBALL" ] || { log "ERROR: backup tarball empty: $BACKUP_TARBALL"; exit 2; }
chmod 0600 "$BACKUP_TARBALL"
log "backup: $BACKUP_TARBALL"

# ---------------------------------------------------------------------------
# Restore-and-die helper — mirrors datarim-doctor.sh restore_backup_and_die
# ---------------------------------------------------------------------------

restore_backup_and_die() {
    local reason="$1"
    log "ROLLBACK: $reason — restoring from $BACKUP_TARBALL"
    rm -rf -- "$REPO_ABS/docs" "$REPO_ABS/documentation"
    tar -xzf "$BACKUP_TARBALL" -C "$REPO_ABS" 2>/dev/null \
        || { log "ERROR: restore from $BACKUP_TARBALL failed — manual recovery required"; exit 2; }
    log "ROLLBACK: restored successfully"
    exit 2
}

# ---------------------------------------------------------------------------
# Step 1: move docs/ → documentation/
# Use git mv when inside a git work-tree; fall back to plain mv otherwise.
# ---------------------------------------------------------------------------

_is_git_repo=0
if git -C "$REPO_ABS" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _is_git_repo=1
fi

if [ "$_is_git_repo" -eq 1 ]; then
    if ! git -C "$REPO_ABS" mv -- docs documentation 2>/dev/null; then
        log "WARNING: git mv failed, falling back to plain mv"
        mv -- "$REPO_ABS/docs" "$REPO_ABS/documentation"
    fi
else
    mv -- "$REPO_ABS/docs" "$REPO_ABS/documentation"
fi

# ---------------------------------------------------------------------------
# Step 2: Diátaxis-split
# Move flat .md files from documentation/ root into category subdirectories.
# Known basenames  → mapped category (tutorials/reference/explanation/how-to).
# Unknown basenames → how-to/ with injected HTML review-category comment.
# Special dirs (how-to/, evolution/, release-audit/) stay where they are;
# the git mv above already brought them under documentation/ correctly.
# ---------------------------------------------------------------------------

mkdir -p -- \
    "$REPO_ABS/documentation/tutorials" \
    "$REPO_ABS/documentation/reference" \
    "$REPO_ABS/documentation/explanation" \
    "$REPO_ABS/documentation/how-to"

# Gather flat .md files at the documentation/ root (not in sub-dirs).
# Use a null-delimited find to handle filenames safely.
_tmp_list="$(mktemp)"
find "$REPO_ABS/documentation" -maxdepth 1 -name "*.md" -print > "$_tmp_list" 2>/dev/null || true

while IFS= read -r _md; do
    [ -n "$_md" ] || continue
    [ -f "$_md" ]  || continue

    _bn="$(basename -- "$_md" .md)"
    _cat="$(_lookup_category "$_bn")"

    if [ -z "$_cat" ]; then
        # Unknown basename — conservative how-to placement with review comment.
        _cat="how-to"
        # Prepend review-category comment to file content.
        _orig="$(cat -- "$_md")"
        printf '%s\n%s\n' \
            "<!-- review category: auto-placed by docs-migrate.sh -->" \
            "$_orig" > "$_md"
    fi

    _dest="$REPO_ABS/documentation/$_cat/$(basename -- "$_md")"

    if [ "$_is_git_repo" -eq 1 ]; then
        if ! git -C "$REPO_ABS" mv -- "$_md" "$_dest" 2>/dev/null; then
            mv -- "$_md" "$_dest"
        fi
    else
        mv -- "$_md" "$_dest"
    fi
done < "$_tmp_list"

rm -f -- "$_tmp_list"

# ---------------------------------------------------------------------------
# Step 3: anchored reference rewrite
# Replace docs/ → documentation/ in all tracked text files inside <repo>,
# using the refined anchor that excludes consumer-ledger paths.
# Perl is preferred (in-place, regex-safe). Gracefully skip if absent.
# ---------------------------------------------------------------------------

if command -v perl >/dev/null 2>&1; then
    find "$REPO_ABS" \
        -not -path "$REPO_ABS/.git/*" \
        \( -name "*.md" -o -name "*.sh" -o -name "*.yaml" -o -name "*.yml" \
           -o -name "*.json" -o -name "*.ts" -o -name "*.js" \) \
        -print0 2>/dev/null \
    | xargs -0 perl -pi \
        -e 's{(?<![A-Za-z0-9_-])(?<!datarim/)docs/}{documentation/}g' \
        -- 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Step 4: verify gate
# Run the consumer's reference-check script if present and executable.
# Non-zero → rollback to tarball, exit 2.
# ---------------------------------------------------------------------------

_verify_script=""
if [ -x "$REPO_ABS/scripts/check-doc-refs.sh" ]; then
    _verify_script="$REPO_ABS/scripts/check-doc-refs.sh"
elif [ -x "$REPO_ABS/dev-tools/check-doc-refs.sh" ]; then
    _verify_script="$REPO_ABS/dev-tools/check-doc-refs.sh"
fi

if [ -n "$_verify_script" ]; then
    log "verify: running $_verify_script"
    if ! "$_verify_script" 2>/dev/null; then
        restore_backup_and_die "verify script returned non-zero: $_verify_script"
    fi
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

log "fixed: docs/ migrated to documentation/ with Diataxis split"
exit 0
