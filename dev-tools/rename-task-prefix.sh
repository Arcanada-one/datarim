#!/usr/bin/env bash
# rename-task-prefix.sh -- reusable, collision-safe task-prefix rename (TUNE-0368).
#
# Generalises the one-off MAINT-0005 rename (ADR->ADSR) into a repeatable safe
# operation. Renames OLD-NNNN task references to NEW-NNNN across a scope, using a
# pure Python anchored classifier (lib/prefix-rename-classify.py) that decides
# per line whether each OLD-NNNN token is a task reference (rename) or a homograph
# to protect (keep) -- e.g. ADR-0001 as "Architecture Decision Record", which a
# blind sed once corrupted across 33 rank-1 mandate refs.
#
# The tool NEVER commits, pushes, or deletes outside a rename, and defaults to a
# non-destructive dry-run. Take a `git stash` / tar backup before --apply.
#
# API:
#   rename-task-prefix.sh --old OLD --new NEW [flags]
#     --old OLD              OLD task prefix (required)
#     --new NEW              NEW task prefix (required)
#     --path P               file or dir in scope (repeatable; default: datarim CLAUDE.md)
#     --exclude-anchor S     line containing literal S is never renamed (repeatable)
#     --include-anchor S     collision number renames only on a line matching S (repeatable)
#     --collision-number N   4-digit number shared with a homograph (repeatable)
#     --rename-files         also git-mv files named OLD-NNNN-* (path-exclude-aware)
#     --registry-file F      assert F has a `| NEW |` row and no `| OLD |` row (verify)
#     --apply                perform the rewrite (default is dry-run preview)
#     --verify               run the V-AC sweep only
#     -h|--help              usage
#
# Exit codes: 0 ok | 1 verify failure | 2 usage/IO error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PY_LIB="$SCRIPT_DIR/lib/prefix-rename-classify.py"

OLD=""
NEW=""
MODE="dry-run"
RENAME_FILES=0
REGISTRY_FILE=""
PATHS=()
EXCLUDES=()
INCLUDES=()
COLLISIONS=()

usage() {
    sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-2}"
}

die() { printf 'rename-task-prefix: %s\n' "$1" >&2; exit "${2:-2}"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --old)              [ $# -ge 2 ] || usage; OLD="$2"; shift 2 ;;
        --new)              [ $# -ge 2 ] || usage; NEW="$2"; shift 2 ;;
        --path)             [ $# -ge 2 ] || usage; PATHS+=("$2"); shift 2 ;;
        --exclude-anchor)   [ $# -ge 2 ] || usage; EXCLUDES+=("$2"); shift 2 ;;
        --include-anchor)   [ $# -ge 2 ] || usage; INCLUDES+=("$2"); shift 2 ;;
        --collision-number) [ $# -ge 2 ] || usage; COLLISIONS+=("$2"); shift 2 ;;
        --registry-file)    [ $# -ge 2 ] || usage; REGISTRY_FILE="$2"; shift 2 ;;
        --rename-files)     RENAME_FILES=1; shift ;;
        --apply)            MODE="apply"; shift ;;
        --verify)           MODE="verify"; shift ;;
        -h|--help)          usage 0 ;;
        *)                  die "unknown argument: $1" ;;
    esac
done

[ -n "$OLD" ] || die "--old is required"
[ -n "$NEW" ] || die "--new is required"
[ -f "$PY_LIB" ] || die "classifier not found: $PY_LIB"

# Default scope when none given.
if [ "${#PATHS[@]}" -eq 0 ]; then
    for p in datarim CLAUDE.md; do
        if [ -e "$p" ]; then PATHS+=("$p"); fi
    done
    [ "${#PATHS[@]}" -gt 0 ] || die "no default scope found (datarim/ or CLAUDE.md); pass --path"
fi

# Assemble the shared classifier argument vector (paths + anchors + collisions).
py_common_args() {
    local -a a=(--old "$OLD" --new "$NEW")
    local x
    for x in "${PATHS[@]}";      do a+=(--path "$x"); done
    for x in "${EXCLUDES[@]}";   do a+=(--exclude-anchor "$x"); done
    for x in "${INCLUDES[@]}";   do a+=(--include-anchor "$x"); done
    for x in "${COLLISIONS[@]}"; do a+=(--collision-number "$x"); done
    printf '%s\0' "${a[@]}"
}

run_py() {
    # $1 = mode flag (--dry-run|--apply|--verify)
    local mode_flag="$1"; shift
    local -a args=()
    while IFS= read -r -d '' item; do args+=("$item"); done < <(py_common_args)
    python3 "$PY_LIB" "${args[@]}" "$mode_flag"
}

path_excluded() {
    # 0 (true) if $1 contains any exclude-anchor substring.
    local p="$1" a
    for a in "${EXCLUDES[@]}"; do
        case "$p" in *"$a"*) return 0 ;; esac
    done
    return 1
}

do_file_renames() {
    local f base dir newbase
    for p in "${PATHS[@]}"; do
        [ -d "$p" ] || continue
        while IFS= read -r -d '' f; do
            path_excluded "$f" && continue
            base="$(basename "$f")"
            dir="$(dirname "$f")"
            newbase="$NEW-${base#"$OLD"-}"
            if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
               git -C "$dir" ls-files --error-unmatch "$base" >/dev/null 2>&1; then
                git -C "$dir" mv "$base" "$newbase"
            else
                mv "$f" "$dir/$newbase"
            fi
            printf 'renamed file: %s -> %s/%s\n' "$f" "$dir" "$newbase"
        done < <(find "$p" -type f -name "$OLD-[0-9][0-9][0-9][0-9]-*" -print0)
    done
}

registry_assert() {
    # Exit non-zero if registry row not migrated. No-op when unset.
    [ -n "$REGISTRY_FILE" ] || return 0
    [ -f "$REGISTRY_FILE" ] || die "registry file not found: $REGISTRY_FILE"
    local ok=0
    if ! grep -qE "^\| *$NEW *\|" "$REGISTRY_FILE"; then
        printf 'REGISTRY FAIL: no "| %s |" row in %s\n' "$NEW" "$REGISTRY_FILE" >&2
        ok=1
    fi
    if grep -qE "^\| *$OLD *\|" "$REGISTRY_FILE"; then
        printf 'REGISTRY FAIL: stale "| %s |" row still in %s\n' "$OLD" "$REGISTRY_FILE" >&2
        ok=1
    fi
    return "$ok"
}

run_verify() {
    local rc=0
    run_py --verify || rc=1
    registry_assert || rc=1
    return "$rc"
}

case "$MODE" in
    dry-run)
        run_py --dry-run
        printf '\n--- Next Step ---\nPreview only, nothing written. Re-run with --apply after taking a backup (git stash / tar).\n'
        ;;
    apply)
        if [ "$RENAME_FILES" -eq 1 ]; then do_file_renames; fi
        run_py --apply
        printf '\n--- Verifying ---\n'
        if run_verify; then
            printf '\n--- Next Step ---\nRename applied and verified. Review the git diff, migrate the CLAUDE.md registry row, then commit.\n'
        else
            die "post-apply verification FAILED -- inspect residue above" 1
        fi
        ;;
    verify)
        if run_verify; then
            printf '\n--- Next Step ---\nVerification passed.\n'
        else
            die "verification FAILED" 1
        fi
        ;;
esac
