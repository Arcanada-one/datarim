#!/usr/bin/env bash
# Pre-overwrite backup primitive for critical Datarim KB files.
#
# backup_critical_kb_file <repo-root> <relpath-under-datarim>
#   If the target exists and is non-empty, copy it to
#   datarim/.backups/<basename>.<ISO-ts>.bak before it is overwritten, so a
#   stray truncation (the awk-with-/dev/null incident class) or an inter-agent
#   race can be recovered byte-for-byte. FIFO rotation keeps the most-recent
#   DR_KB_BACKUP_KEEP copies per basename (default 10). The backup dir is
#   created chmod 700; the critical section is serialised with the portable
#   mkdir-based lock reused from plugin-system.sh.
#
# Fail-soft by contract: ANY error (unwritable dir, missing lock lib, copy
# failure, path-traversal attempt) logs to stderr and RETURNS 0. The primitive
# protects data on a best-effort basis; it must never block or abort the write
# it precedes - blocking a legitimate write to "protect" it is worse than the
# (rare) failed backup.
#
# Generalises the doctor's existing pre-write backup convention (umask 077 +
# chmod) and reuses acquire_plugin_lock - no new primitives.

KB_BACKUP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the portable lock primitive. Fail-soft: if it cannot be sourced we
# still back up (without the lock) rather than refuse.
if [ -f "${KB_BACKUP_LIB_DIR}/plugin-system.sh" ]; then
    # shellcheck source=plugin-system.sh
    . "${KB_BACKUP_LIB_DIR}/plugin-system.sh" 2>/dev/null || true
fi

# Critical-file basename allowlist - files that multiple agents concurrently
# write and whose loss is expensive. The hook enforcement layer uses this to
# decide which overwrites to back up; internal callers (doctor, pre-archive)
# may pass ANY relpath under datarim/ and the backup still runs.
KB_BACKUP_CRITICAL="backlog.md backlog-archive.md tasks.md activeContext.md progress.md"

_kb_backup_warn() { printf 'WARN: kb-backup: %s\n' "$*" >&2; }

# Return 0 if <basename> is in the critical-file allowlist. Used by the hook
# guard to gate the backup side-effect to the files worth protecting.
kb_is_critical_basename() {
    local cand="$1" name
    for name in $KB_BACKUP_CRITICAL; do
        [ "$cand" = "$name" ] && return 0
    done
    return 1
}

backup_critical_kb_file() {
    local repo_root="$1" relpath="$2"

    # --- input validation (fail-soft: warn + return 0) ----------------------
    if [ -z "$repo_root" ] || [ -z "$relpath" ]; then
        _kb_backup_warn "missing arg (repo-root + relpath required)"
        return 0
    fi
    # Reject path-traversal / absolute escapes outright (Security Mandate S1).
    case "$relpath" in
        /*|*..*)
            _kb_backup_warn "refusing unsafe relpath: $relpath"
            return 0
            ;;
    esac
    if [ ! -d "$repo_root/datarim" ]; then
        _kb_backup_warn "no datarim/ under repo-root: $repo_root"
        return 0
    fi

    local target="$repo_root/datarim/$relpath"
    # Nothing to back up unless the target exists and is non-empty.
    if [ ! -f "$target" ] || [ ! -s "$target" ]; then
        return 0
    fi

    local backup_dir="$repo_root/datarim/.backups"
    local base ts dest
    base="$(basename "$relpath")"
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    dest="$backup_dir/$base.$ts.bak"
    # Avoid a same-second collision silently overwriting a prior backup: if the
    # ISO-second dest already exists, append a short PID-based discriminator
    # (still sorts after the colliding name for FIFO rotation).
    if [ -e "$dest" ]; then
        dest="$backup_dir/$base.$ts-$$.bak"
    fi

    # --- locked critical section (best-effort lock) -------------------------
    local lock_dir="$backup_dir/.lock.$base"
    local have_lock=0
    if command -v acquire_plugin_lock >/dev/null 2>&1; then
        # short timeout - a backup must not stall the write it precedes
        if acquire_plugin_lock "$lock_dir" "${DR_KB_BACKUP_LOCK_TIMEOUT:-5}" 2>/dev/null; then
            have_lock=1
        fi
    fi

    # Refuse a pre-existing symlinked backup dir: an attacker who pre-creates
    # datarim/.backups as a symlink to a sensitive dir would otherwise have us
    # chmod the target and land copies inside it. We own the real dir or we do
    # nothing (fail-soft).
    if [ -L "$backup_dir" ]; then
        _kb_backup_warn "refusing symlinked backup dir: $backup_dir"
        [ "$have_lock" = 1 ] && release_plugin_lock "$lock_dir"
        return 0
    fi
    # Create the backup dir privately. umask in a subshell so we don't mutate
    # the caller's umask; explicit chmod because some platforms ignore umask.
    (
        umask 077
        mkdir -p "$backup_dir" 2>/dev/null
    ) || { _kb_backup_warn "cannot create $backup_dir"; [ "$have_lock" = 1 ] && release_plugin_lock "$lock_dir"; return 0; }
    chmod 700 "$backup_dir" 2>/dev/null || true

    # Copy preserving content; if cp fails (read-only dir etc.) -> fail-soft.
    if ! cp -p "$target" "$dest" 2>/dev/null; then
        _kb_backup_warn "backup copy failed: $target -> $dest"
        [ "$have_lock" = 1 ] && release_plugin_lock "$lock_dir"
        return 0
    fi
    chmod 600 "$dest" 2>/dev/null || true

    # --- FIFO rotation: keep the N most-recent .bak for this basename -------
    local keep="${DR_KB_BACKUP_KEEP:-10}"
    case "$keep" in ''|*[!0-9]*) keep=10 ;; esac
    # List oldest-first by name (ISO-ts sorts lexically == chronologically),
    # drop all but the last $keep.
    local count
    count="$(find "$backup_dir" -maxdepth 1 -name "$base.*.bak" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$count" -gt "$keep" ]; then
        local evict=$(( count - keep ))
        find "$backup_dir" -maxdepth 1 -name "$base.*.bak" 2>/dev/null \
            | sort | head -n "$evict" \
            | while IFS= read -r old; do rm -f "$old" 2>/dev/null || true; done
    fi

    [ "$have_lock" = 1 ] && release_plugin_lock "$lock_dir"
    return 0
}

# If invoked directly, dispatch (handy for the hook / manual use).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    backup_critical_kb_file "$@"
fi
