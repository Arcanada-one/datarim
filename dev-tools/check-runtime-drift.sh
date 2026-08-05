#!/usr/bin/env bash
# check-runtime-drift.sh — a runtime pinned to a feature-worktree must not
# silently serve stale rules.
#
# Scope: under symlink-mode the agent runtime (`$CLAUDE_DIR/{skills,commands,
# agents,...}`) points into a git checkout of the framework. When that checkout
# sits on a feature branch — e.g. a bugfix worktree that was never retargeted —
# every agent on the host quietly runs old skills, old commands and an old
# VERSION while the repo, the fleet and the release notes have moved on. This
# check makes that state loud.
#
# Drift conditions (any → FAIL):
#   D1 a runtime scope symlink resolves into a git checkout whose HEAD branch
#      is not `main` (detached HEAD counts as drift unless it sits exactly on
#      a `v*` release tag — a tag-pinned runtime is a legitimate deployment);
#   D2 runtime scopes resolve into DIFFERENT checkouts (mixed runtime).
#
# Not drift: copy-mode installs (scope is a real directory, not a symlink) —
# copy-mode currency is the installer's business, not a symlink-target property.
#
# Contract (per CLAUDE.md § Validation Discipline):
#   pure shell; --check mode; exit 0 = PASS, exit 1 = FAIL, exit 2 = usage.
#
# Usage:
#   check-runtime-drift.sh --check [--claude-dir <path>] [--branch main]
set -euo pipefail

claude_dir="${CLAUDE_DIR:-$HOME/.claude}" ; expect_branch="main" ; mode=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check) mode=check; shift ;;
        --claude-dir) claude_dir="${2:-}"; shift 2 ;;
        --branch) expect_branch="${2:-main}"; shift 2 ;;
        -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
    esac
done
[ "$mode" = check ] || { echo "ERROR: --check is required" >&2; exit 2; }
[ -d "$claude_dir" ] || { echo "ERROR: claude dir '$claude_dir' not found" >&2; exit 2; }

drift=0
seen_root=""
for scope in skills commands agents; do
    link="$claude_dir/$scope"
    # -e follows symlinks, so a BROKEN symlink would be skipped as "absent" —
    # exactly the silent state this check exists to catch. Test -L separately.
    [ -e "$link" ] || [ -L "$link" ] || continue
    [ -L "$link" ] || { echo "INFO: $scope is a real directory (copy-mode) — skipped"; continue; }
    target="$(readlink -f "$link" || true)"
    [ -n "$target" ] && [ -d "$target" ] || { echo "FAIL: $scope symlink is broken ($link)"; drift=1; continue; }
    root="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -z "$root" ]; then
        echo "INFO: $scope target is not a git checkout — skipped"
        continue
    fi
    branch="$(git -C "$root" symbolic-ref --short -q HEAD || echo DETACHED)"
    version="$( [ -f "$root/VERSION" ] && tr -d ' \t\n' < "$root/VERSION" || echo '?' )"
    if [ -n "$seen_root" ] && [ "$root" != "$seen_root" ]; then
        echo "FAIL: mixed runtime — $scope resolves into '$root' but an earlier scope resolved into '$seen_root'"
        drift=1
    fi
    seen_root="$root"
    if [ "$branch" = "$expect_branch" ]; then
        echo "OK: $scope -> $root (branch $branch, VERSION $version)"
    elif [ "$branch" = DETACHED ] && git -C "$root" describe --tags --exact-match --match 'v*' >/dev/null 2>&1; then
        echo "OK: $scope -> $root (detached on release tag $(git -C "$root" describe --tags --exact-match --match 'v*'), VERSION $version)"
    else
        echo "FAIL: runtime drift — $scope resolves into '$root' on branch '$branch' (VERSION $version), expected '$expect_branch'. Agents on this host are serving a feature-worktree's rules."
        drift=1
    fi
done

if [ "$drift" -ne 0 ]; then
    echo "RESULT: FAIL — repoint the runtime symlinks at a current '$expect_branch' checkout (see documentation/tutorials/getting-started.md § installation modes)." >&2
    exit 1
fi
echo "RESULT: PASS — runtime symlinks resolve to a '$expect_branch' checkout"
exit 0
