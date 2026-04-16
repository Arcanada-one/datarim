#!/usr/bin/env bash
# pre-archive-check.sh — pre-archive clean-git gate (TUNE-0003 Proposal 1)
#
# Verifies that every git repository touched by a task has a clean working tree
# before `/dr-archive` proceeds. Codifies the contract documented in
# commands/dr-archive.md step 0.
#
# Usage:
#   ./scripts/pre-archive-check.sh REPO_PATH [REPO_PATH...]
#
# Exit codes:
#   0  all repos clean (proceed with archive)
#   1  at least one repo dirty (block archive)
#   2  usage error (no args, path missing, path not a git repo)
#
# Output:
#   stdout — dirty repo paths, one per line (machine-readable).
#   stderr — human-facing summary + 3-way prompt template (commit/accept/abort)
#            so the caller (Claude Code during /dr-archive) can present it.
#
# Read-only: runs `git status --porcelain` only. No mutation of any repo.

set -u

print_usage() {
    cat >&2 <<'EOF'
Usage: pre-archive-check.sh REPO_PATH [REPO_PATH...]

  Checks each REPO_PATH for a clean git working tree.

Exit codes:
  0 - all clean (archive may proceed)
  1 - at least one repo dirty (archive blocked — see stderr for options)
  2 - usage error
EOF
}

if [ "$#" -eq 0 ]; then
    print_usage
    exit 2
fi

# Validate every path before checking status, so a typo fails fast.
for repo in "$@"; do
    if [ ! -e "$repo" ]; then
        echo "ERROR: path not found: $repo" >&2
        exit 2
    fi
    if [ ! -d "$repo/.git" ] && ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
        echo "ERROR: not a git repository: $repo" >&2
        exit 2
    fi
done

# Collect dirty repos.
dirty_repos=()
for repo in "$@"; do
    status_output=$(git -C "$repo" status --porcelain 2>/dev/null || true)
    if [ -n "$status_output" ]; then
        dirty_repos+=("$repo")
    fi
done

# Clean case → silent success.
if [ "${#dirty_repos[@]}" -eq 0 ]; then
    echo "OK: $# repo(s) clean — archive may proceed" >&2
    exit 0
fi

# Dirty case → list on stdout (machine-readable) + prompt on stderr.
for repo in "${dirty_repos[@]}"; do
    echo "$repo"
done

{
    echo ""
    echo "BLOCKED: ${#dirty_repos[@]} repo(s) have uncommitted changes:"
    for repo in "${dirty_repos[@]}"; do
        echo "  - $repo"
    done
    echo ""
    echo "Choose one:"
    echo "  a. Commit now       — land the changes, then re-run the archive."
    echo "  b. Accept pending state — record the reason in the archive doc's"
    echo "                            'Known Outstanding State' section."
    echo "  c. Abort            — return to /dr-do or fix manually."
    echo ""
    echo "Applied != committed != canonical. See TUNE-0003 for rationale."
} >&2

exit 1
