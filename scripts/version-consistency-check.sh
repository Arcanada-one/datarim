#!/usr/bin/env bash
# version-consistency-check.sh — pre-archive version-consistency gate (TUNE-0080).
#
# Contract: when the framework's `VERSION` file changed in HEAD->working-tree,
# all consumer files (CLAUDE.md, README.md, docs/) must reference the new
# version. If any still cite the old version, archive is blocked.
#
# Source: recurring class — VERSION bumped but README/CLAUDE.md left stale
# (caught manually in prior archive cycles; cheap one-liner closes the gap).
#
# Usage:
#   version-consistency-check.sh REPO_PATH
#   version-consistency-check.sh --allow-version-lag REPO_PATH
#
# Exit codes:
#   0  archive may proceed (VERSION unchanged, or all consumers aligned, or override)
#   1  blocked (VERSION bumped + at least one consumer cites old version)
#   2  usage error (no args, not a git repo, missing path)
#
# Read-only: runs `git show HEAD:VERSION` + plain text reads. No mutation.

set -u

print_usage() {
    cat >&2 <<'EOF'
Usage:
  version-consistency-check.sh [--allow-version-lag] REPO_PATH

If REPO_PATH/VERSION changed in HEAD->working-tree, scan
REPO_PATH/{CLAUDE.md,README.md,docs/} for the old version string. Any hit
blocks the archive (exit 1). Use --allow-version-lag to override (exit 0
with stderr warning).

Exit: 0 ok / 1 blocked / 2 usage error
EOF
}

# Parse args (one optional flag + one positional).
allow_lag=0
repo=""
while [ $# -gt 0 ]; do
    case "$1" in
        --allow-version-lag) allow_lag=1; shift ;;
        -h|--help) print_usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "ERROR: unknown flag: $1" >&2; print_usage; exit 2 ;;
        *)
            if [ -n "$repo" ]; then
                echo "ERROR: only one REPO_PATH supported" >&2
                exit 2
            fi
            repo="$1"; shift ;;
    esac
done

if [ -z "$repo" ]; then
    print_usage
    exit 2
fi

if [ ! -d "$repo/.git" ] && ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: not a git repo: $repo" >&2
    exit 2
fi

# Read working-tree VERSION (current). Tolerate trailing whitespace.
if [ ! -f "$repo/VERSION" ]; then
    # No VERSION file at all — nothing to check.
    exit 0
fi
new=$(tr -d '[:space:]' < "$repo/VERSION")

# Read HEAD's VERSION. May not exist (initial bootstrap commit).
if old_raw=$(git -C "$repo" show HEAD:VERSION 2>/dev/null); then
    old=$(printf '%s' "$old_raw" | tr -d '[:space:]')
else
    # No prior VERSION in HEAD — nothing to check (initial commit).
    exit 0
fi

# VERSION unchanged → skip (most archives don't bump).
if [ "$old" = "$new" ]; then
    exit 0
fi

# Empty old (shouldn't happen if file existed but be defensive).
if [ -z "$old" ]; then
    exit 0
fi

# VERSION bumped. Scan consumers for the OLD version string.
# Targets: CLAUDE.md, README.md (top-of-file version refs).
# `docs/` is intentionally excluded: evolution-log / release-notes / changelog
# legitimately reference historical versions — they're an append-only ledger,
# not a current-state surface. The recurring drift class concerned CLAUDE.md
# "Version:" line and README.md badge only.
hits=""
scan_targets=()
[ -f "$repo/CLAUDE.md" ] && scan_targets+=("$repo/CLAUDE.md")
[ -f "$repo/README.md" ] && scan_targets+=("$repo/README.md")

if [ ${#scan_targets[@]} -eq 0 ]; then
    # No consumers to check.
    exit 0
fi

# grep -F: literal match (no regex). -r: recurse. -l: list files only.
# Quote `$old` to keep dot literal.
if hits=$(grep -Frln "$old" "${scan_targets[@]}" 2>/dev/null); then
    : # found matches
else
    hits=""
fi

if [ -z "$hits" ]; then
    # All consumers updated.
    exit 0
fi

# Hit list non-empty. Strip repo prefix for readability.
relative_hits=$(printf '%s\n' "$hits" | sed "s|^$repo/||")

if [ "$allow_lag" -eq 1 ]; then
    cat >&2 <<EOF
WARNING (--allow-version-lag): VERSION bumped $old -> $new but the following still cite $old:
$relative_hits
Override accepted; archive proceeds.
EOF
    exit 0
fi

cat <<EOF
BLOCKED: VERSION bumped $old -> $new but the following still cite $old:
$relative_hits

Either update the lagging files to $new, or pass --allow-version-lag if the
lag is intentional. See commands/dr-archive.md Step 0.6.
EOF
exit 1
