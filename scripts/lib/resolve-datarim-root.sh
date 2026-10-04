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

# Resolve only explicitly installed projects; historical KB files never opt a
# directory into the framework. The Python resolver checks physical paths and
# nested repository context grants identically to the Jev entrypoints.
_DR_SCOPE_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/project_scope.py"
resolve_datarim_root() {
    local start dr_root extra
    start="${1:-$PWD}"
    dr_root="$(python3 "$_DR_SCOPE_SCRIPT" "$start")" || return 1
    if ! _dr_is_kb "$dr_root/datarim"; then
        printf 'ERROR: enabled project has no initialized datarim/ state\n' >&2
        return 1
    fi
    extra="$(find "$dr_root" -mindepth 2 -maxdepth 5 -type d -name datarim \
        -not -path '*/.git/*' -not -path '*/.datarim-runtime/*' 2>/dev/null \
        | while IFS= read -r d; do _dr_is_kb "$d" && printf '%s\n' "$d"; done \
        | head -n 5)"
    if [ -n "$extra" ]; then
        printf 'WARN: additional KB state exists below the enabled project:\n%s\n' "$extra" >&2
    fi
    printf '%s\n' "$dr_root"
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
