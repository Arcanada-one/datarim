#!/bin/bash
set -euo pipefail
# check-shared-tree-conflict.sh — plan-time shared-tree foreign-edit probe
#
# Plan-time probe: for each file a plan names as an EDIT target, report whether
# that file already carries uncommitted changes in the shared working tree that
# are NOT this task's — i.e. a parallel session's in-flight work. When it does,
# the planner should isolate the commit via a git worktree off a clean base
# rather than `git add <file>` (which would drag the foreign hunks in).
#
# Rationale (Multi-Agent Workspace Discipline): the root git workspace is shared
# by parallel sessions; a mixed-file commit silently captures another session's
# unstaged edits. Catching this at /dr-plan (not at /dr-do commit time) lets the
# worktree-isolation decision be made deliberately.
#
# Usage:
#   check-shared-tree-conflict.sh [--base <ref>] [--repo <dir>] <file> [<file>...]
#
# Options:
#   --base <ref>   base ref to diff against (default: origin/main, then HEAD)
#   --repo <dir>   git repo the files live in (default: the file's own repo)
#
# Exit codes:
#   0  no shared-tree conflict on any named file (clean to commit directly)
#   1  >=1 file carries uncommitted changes vs base (isolate via worktree)
#   2  usage error
#
# Fail-open: a file outside any git repo, or an unreadable base, is reported as
# "not-tracked / cannot-probe" and does NOT by itself set exit 1 — the probe
# never blocks on its own infrastructure failure (advisory contract).

BASE=""
REPO_OVERRIDE=""
FILES=()

while [ $# -gt 0 ]; do
    case "$1" in
        --base) shift; [ $# -gt 0 ] || { echo "ERROR: --base needs a ref" >&2; exit 2; }; BASE="$1"; shift ;;
        --repo) shift; [ $# -gt 0 ] || { echo "ERROR: --repo needs a dir" >&2; exit 2; }; REPO_OVERRIDE="$1"; shift ;;
        --) shift; while [ $# -gt 0 ]; do FILES+=("$1"); shift; done ;;
        -*) echo "ERROR: unknown flag $1" >&2; exit 2 ;;
        *) FILES+=("$1"); shift ;;
    esac
done

[ "${#FILES[@]}" -gt 0 ] || { echo "usage: check-shared-tree-conflict.sh [--base ref] [--repo dir] <file>..." >&2; exit 2; }

conflict=0

for f in "${FILES[@]}"; do
    # Resolve the repo for this file.
    if [ -n "$REPO_OVERRIDE" ]; then
        repo="$REPO_OVERRIDE"
    else
        repo="$(dirname -- "$f")"
    fi

    if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        printf 'CANNOT-PROBE: %s (not inside a git work tree)\n' "$f"
        continue
    fi

    # Path relative to the repo top, so `git diff` resolves it. Canonicalise both
    # sides (resolve symlinks like /tmp -> /private/tmp) so relpath does not emit a
    # spurious `../../..` that git then treats as a non-matching path.
    top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || echo "")"
    [ -n "$top" ] || { printf 'CANNOT-PROBE: %s (no toplevel)\n' "$f"; continue; }
    top="$(cd "$top" && pwd -P)"
    rel="$(python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), sys.argv[2]))' "$f" "$top" 2>/dev/null || echo "$f")"

    # Pick a base ref: explicit, else origin/main, else HEAD.
    base="$BASE"
    if [ -z "$base" ]; then
        if git -C "$top" rev-parse --verify -q origin/main >/dev/null 2>&1; then
            base="origin/main"
        else
            base="HEAD"
        fi
    fi

    # Does the working-tree copy differ from base? (staged + unstaged.)
    if git -C "$top" diff --quiet "$base" -- "$rel" 2>/dev/null; then
        printf 'CLEAN: %s (matches %s)\n' "$rel" "$base"
    else
        printf 'CONFLICT: %s carries uncommitted changes vs %s — isolate via git worktree\n' "$rel" "$base"
        conflict=1
    fi
done

exit "$conflict"
