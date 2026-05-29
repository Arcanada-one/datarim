#!/usr/bin/env bash
# Canonical Datarim KB-root resolver.
#
# The single source-of-truth implementation of the path-resolution rule
# documented in skills/datarim-system/path-and-storage.md. Every consumer that
# needs the location of the knowledge base sources this file and calls
# resolve_datarim_root - eliminating the three divergent walk-up reimplementations
# that produced nested datarim/datarim/ directories and the missed docs->history
# migration.
#
# Contract: --root MEANS REPO-ROOT everywhere. resolve_datarim_root echoes the
# repo-root (the parent of the KB-marked datarim/), NOT the datarim/ dir itself.
# Consumers derive "$repo_root/datarim" internally.
#
# Functions:
#   resolve_datarim_root [start_dir]   echoes <repo-root>; exit 1 if no KB found
#   assert_not_nested_datarim <root>   exit 1 + stderr if <root> is inside a datarim/
#
# Safe to source under `set -euo pipefail`: every function uses locals, returns
# explicit codes, and never relies on the caller's shell options.

# A real KB carries at least one of the canonical operational files. A plain
# datarim/ without markers (e.g. the framework source-tree code/datarim/) is
# NOT a KB.
_dr_is_kb() {
    [ -d "$1" ] && { [ -f "$1/tasks.md" ] || [ -f "$1/backlog.md" ]; }
}

# Echo the repo-root for the given start directory (default: $PWD).
#
# Resolution order (mirrors path-and-storage.md Quick Shell Check):
#   1. git-toplevel anchor - if inside a git repo AND <toplevel>/datarim is a
#      KB, return the toplevel. Deterministic regardless of nested/sibling
#      datarim/ directories ("one KB per git repo").
#   2. walk-up fallback - first parent whose datarim/ is a KB.
#   3. not found -> exit 1 + stderr.
# Emits a WARN advisory to stderr when more than one KB-marked datarim/ is
# visible below the resolved anchor (a misplaced KB).
resolve_datarim_root() {
    local start dr_root cur
    start="${1:-$PWD}"
    # Normalise to an absolute, existing directory.
    if [ ! -d "$start" ]; then
        printf 'ERROR: resolve_datarim_root: start dir not found: %s\n' "$start" >&2
        return 1
    fi
    start="$(cd "$start" && pwd)"

    dr_root=""
    # 1) git-toplevel anchor. git resolves symlinks (macOS /var -> /private/var),
    #    so we compare physical paths to decide WHICH logical ancestor of $start
    #    is the anchor, then return that ancestor in its logical ($PWD-style)
    #    form - keeping the resolver's output consistent with the walk-up branch
    #    and with the $PWD callers compare against.
    local toplevel="" toplevel_phys=""
    toplevel="$(cd "$start" && git rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$toplevel" ] && _dr_is_kb "$toplevel/datarim"; then
        toplevel_phys="$(cd "$toplevel" && pwd -P)"
        cur="$start"
        while [ "$cur" != "/" ]; do
            if [ "$(cd "$cur" && pwd -P)" = "$toplevel_phys" ]; then
                dr_root="$cur"
                break
            fi
            cur="$(dirname "$cur")"
        done
        # Fallback (start outside the worktree subtree - unusual): logical form
        # of the toplevel itself.
        [ -z "$dr_root" ] && dr_root="$(cd "$toplevel" && pwd)"
    else
        # 2) walk-up fallback from start.
        cur="$start"
        while [ "$cur" != "/" ]; do
            if _dr_is_kb "$cur/datarim"; then
                dr_root="$cur"
                break
            fi
            cur="$(dirname "$cur")"
        done
    fi

    if [ -z "$dr_root" ]; then
        printf 'ERROR: datarim/ not found (no directory with tasks.md or backlog.md)\n' >&2
        return 1
    fi

    # 3) advisory: warn if more than one KB-marked datarim/ is visible below the
    #    chosen anchor - signals a misplaced KB to report to the operator.
    local extra=""
    extra="$(find "$dr_root" -mindepth 2 -maxdepth 5 -type d -name datarim \
        -not -path '*/.git/*' 2>/dev/null \
        | while IFS= read -r d; do _dr_is_kb "$d" && printf '%s\n' "$d"; done \
        | head -n 5)"
    if [ -n "$extra" ]; then
        printf 'WARN: multiple KB-marked datarim/ visible - using %s/datarim; also seen:\n%s\n' \
            "$dr_root" "$extra" >&2
    fi

    printf '%s\n' "$dr_root"
    return 0
}

# Refuse a root that is itself inside a datarim/ directory - the datarim/datarim/
# nesting vector. A caller that resolved its root correctly should never trip
# this; it catches a consumer that passed "<repo>/datarim" where repo-root was
# expected, which would otherwise write to "<repo>/datarim/datarim/...".
assert_not_nested_datarim() {
    local root="$1"
    if [ -z "$root" ]; then
        printf 'ERROR: assert_not_nested_datarim: empty root\n' >&2
        return 1
    fi
    # Reject path-traversal escapes outright (Security Mandate S1).
    case "$root" in
        *..*)
            printf 'ERROR: assert_not_nested_datarim: refusing root with "..": %s\n' "$root" >&2
            return 1
            ;;
    esac
    # The basename or any path component being "datarim" while a parent datarim/
    # exists means the root sits inside a KB dir. The simplest robust check:
    # the root's own basename is "datarim", or "/datarim/" appears in the path.
    case "/$root/" in
        */datarim/*)
            printf 'ERROR: nested datarim detected - root %q is inside a datarim/ (would create datarim/datarim/)\n' \
                "$root" >&2
            return 1
            ;;
    esac
    return 0
}
