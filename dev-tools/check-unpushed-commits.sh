#!/usr/bin/env bash
# dev-tools/check-unpushed-commits.sh — per-repo unpushed-commits gate.
#
# Determines whether a git repository has commits that exist locally but are
# not yet present on the remote comparison point.  Emits a machine-readable
# verdict token on stdout and writes a rationale line to stderr (suppressed
# by --quiet).
#
# Intended for use in /dr-archive Step 0.12.  Pure read-only; performs no
# network calls, no git writes, and evaluates no user input as code.
#
# Usage:
#   check-unpushed-commits.sh --repo <path> --task-description <path>
#                             [--quiet] [--version] [-h|--help]
#
# Required arguments:
#   --repo <path>               Path to a git working tree.
#   --task-description <path>   Path to a YAML-frontmatter task description
#                               file (used to read the `type:` field).
#
# Optional arguments:
#   --quiet    Suppress stderr rationale; stdout token is unchanged.
#   --version  Print version and exit 0.
#   -h, --help Print this help and exit 0.
#
# Output:
#   stdout: exactly one decision token:
#     stop      — unpushed commits exist AND task type is in {bugfix, feature, refactor}
#     advisory  — unpushed commits exist AND task type is NOT in the trigger set
#     clean     — no unpushed commits, or base was unresolvable (fail-open)
#
# Exit codes:
#   0   decision rendered (any token)
#   2   usage error (missing required arg, repo not a git workdir, unreadable td)
#
# Base-resolution order (first success wins):
#   1. @{u}  — configured upstream-tracking ref
#   2. origin/<default>  — resolved via git symbolic-ref refs/remotes/origin/HEAD
#   3. origin/main  — last-resort fallback
#   On unresolvable base: emit clean + advisory note (fail-open; never false-STOP).

set -uo pipefail

VERSION="1.0.0"
SCRIPT_NAME="check-unpushed-commits.sh"

# Task types that trigger STOP on unpushed commits.
STOP_TYPES="bugfix feature refactor"

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME --repo <path> --task-description <path> [--quiet]
       $SCRIPT_NAME --version
       $SCRIPT_NAME -h | --help

Tokens (stdout):
  stop      unpushed commits AND type in {bugfix, feature, refactor}
  advisory  unpushed commits AND type NOT in trigger set
  clean     no unpushed commits, or base unresolvable (fail-open)

Exit: 0 decision rendered | 2 usage error
EOF
}

# extract_frontmatter_field <file> <key>
# Echoes the value of <key> from the first YAML frontmatter block.
# Strips surrounding quotes/spaces.  Empty output => key missing.
extract_frontmatter_field() {
    local file="$1"
    local key="$2"
    awk -v key="$key" '
        BEGIN { in_fm = 0 }
        /^---[[:space:]]*$/ {
            if (in_fm) { exit }
            in_fm = 1
            next
        }
        in_fm && $0 ~ "^"key":[[:space:]]" {
            sub("^"key":[[:space:]]+", "")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            gsub(/^["\047]|["\047]$/, "")
            print
            exit
        }
    ' "$file"
}

# is_stop_type <type_string>
# Returns 0 (true) if the type is in the STOP_TYPES set.
is_stop_type() {
    local t="$1"
    local candidate
    for candidate in $STOP_TYPES; do
        [ "$t" = "$candidate" ] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
repo=""
task_desc=""
quiet="0"

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)
            shift
            [ $# -gt 0 ] || { printf '%s: --repo requires a path\n' "$SCRIPT_NAME" >&2; exit 2; }
            repo="$1"
            ;;
        --task-description)
            shift
            [ $# -gt 0 ] || { printf '%s: --task-description requires a path\n' "$SCRIPT_NAME" >&2; exit 2; }
            task_desc="$1"
            ;;
        --quiet)
            quiet="1"
            ;;
        --version)
            printf '%s %s\n' "$SCRIPT_NAME" "$VERSION"
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf '%s: unknown flag: %s\n' "$SCRIPT_NAME" "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
[ -n "$repo" ] || { printf '%s: --repo is required\n' "$SCRIPT_NAME" >&2; usage >&2; exit 2; }
[ -n "$task_desc" ] || { printf '%s: --task-description is required\n' "$SCRIPT_NAME" >&2; usage >&2; exit 2; }

# Verify repo is a git working tree
if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s: not a git working tree: %s\n' "$SCRIPT_NAME" "$repo" >&2
    exit 2
fi

[ -r "$task_desc" ] || { printf '%s: cannot read task description: %s\n' "$SCRIPT_NAME" "$task_desc" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Read task type
# ---------------------------------------------------------------------------
task_type="$(extract_frontmatter_field "$task_desc" type)"

# ---------------------------------------------------------------------------
# Shallow-clone advisory
# ---------------------------------------------------------------------------
is_shallow="$(git -C "$repo" rev-parse --is-shallow-repository 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# Base resolution: @{u} -> symbolic-ref -> origin/main
# ---------------------------------------------------------------------------
base=""
base_method=""

# Check for detached HEAD first
current_branch="$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || true)"
if [ -z "$current_branch" ]; then
    # Detached HEAD — no upstream possible
    if [ "$quiet" != "1" ]; then
        printf 'gate: repo=%s base=<detached HEAD> count=0 type=%s -> clean (fail-open: detached HEAD)\n' \
            "$repo" "${task_type:-<missing>}" >&2
    fi
    echo "clean"
    exit 0
fi

# 1. Try @{u} upstream tracking ref
if git -C "$repo" rev-parse --verify "@{u}" >/dev/null 2>&1; then
    base="@{u}"
    base_method="@{u}"
fi

# 2. Try symbolic-ref refs/remotes/origin/HEAD
if [ -z "$base" ]; then
    symref="$(git -C "$repo" symbolic-ref --quiet "refs/remotes/origin/HEAD" 2>/dev/null || true)"
    if [ -n "$symref" ]; then
        # Strip "refs/remotes/" prefix to get e.g. "origin/main" or "origin/trunk"
        symref_short="${symref#refs/remotes/}"
        if git -C "$repo" rev-parse --verify "$symref_short" >/dev/null 2>&1; then
            base="$symref_short"
            base_method="symbolic-ref"
        fi
    fi
fi

# 3. Last-resort: origin/main
if [ -z "$base" ]; then
    if git -C "$repo" rev-parse --verify "origin/main" >/dev/null 2>&1; then
        base="origin/main"
        base_method="last-resort-origin/main"
    fi
fi

# Unresolvable base — fail-open
if [ -z "$base" ]; then
    if [ "$quiet" != "1" ]; then
        printf 'gate: repo=%s base=<unresolvable> count=0 type=%s -> clean (fail-open: no remote base)\n' \
            "$repo" "${task_type:-<missing>}" >&2
    fi
    echo "clean"
    exit 0
fi

# ---------------------------------------------------------------------------
# Count unpushed commits
# ---------------------------------------------------------------------------
count="$(git -C "$repo" rev-list --count "${base}..HEAD" 2>/dev/null || true)"

# If count is empty (rev-list failed for some reason), fail-open
if [ -z "$count" ]; then
    if [ "$quiet" != "1" ]; then
        printf 'gate: repo=%s base=%s count=<error> type=%s -> clean (fail-open: rev-list error)\n' \
            "$repo" "$base" "${task_type:-<missing>}" >&2
    fi
    echo "clean"
    exit 0
fi

# ---------------------------------------------------------------------------
# Decide
# ---------------------------------------------------------------------------
token=""
if [ "$count" -gt 0 ] && is_stop_type "$task_type"; then
    token="stop"
elif [ "$count" -gt 0 ]; then
    token="advisory"
else
    token="clean"
fi

# Defensive invariant: token must be set to one of the three valid values
case "$token" in
    stop|advisory|clean) ;;
    *)
        printf '%s: INTERNAL ERROR: invalid token: %s\n' "$SCRIPT_NAME" "$token" >&2
        exit 2
        ;;
esac

# ---------------------------------------------------------------------------
# Rationale (stderr unless --quiet)
# ---------------------------------------------------------------------------
if [ "$quiet" != "1" ]; then
    shallow_note=""
    [ "$is_shallow" = "true" ] && shallow_note=" [shallow: count may overstate]"
    printf 'gate: repo=%s base=%s(%s) count=%s type=%s -> %s%s\n' \
        "$repo" "$base" "$base_method" "$count" "${task_type:-<missing>}" "$token" "$shallow_note" >&2
fi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
echo "$token"
exit 0
