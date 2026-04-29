#!/usr/bin/env bash
# pre-archive-check.sh — pre-archive clean-git gate (TUNE-0003 Proposal 1, TUNE-0044 shared mode)
#
# Verifies the working-tree state of every git repository touched by a task
# before `/dr-archive` proceeds. Codifies the contract documented in
# commands/dr-archive.md Step 0.1.
#
# Two modes:
#   1. Legacy mode (TUNE-0003) — single-agent project repos must be fully clean.
#        Usage: pre-archive-check.sh REPO_PATH [REPO_PATH...]
#
#   2. Shared mode (TUNE-0044) — multi-agent workspace repos where parallel
#      sessions may have uncommitted hunks under foreign task IDs. Only the
#      current task's own forgotten hunks (or unattributed hunks) block.
#        Usage: pre-archive-check.sh --task-id <ID> --shared <REPO_PATH>
#
# Exit codes:
#   0  archive may proceed (clean / foreign-only)
#   1  archive blocked (dirty in legacy mode; own/mixed/unattributed in shared mode)
#   2  usage error (no args, missing path, bad regex, not a git repo)
#
# Output (legacy mode):
#   stdout — dirty repo paths, one per line.
#   stderr — human-facing 3-way prompt (commit/accept/abort).
#
# Output (shared mode):
#   stdout — TAB-separated per-file classification: <file>\t<klass>\t<task-ids-csv>
#            klass ∈ {own, foreign, mixed, unattributed}.
#   stderr — recipe pointer when blocking; OK summary when foreign-only.
#
# Read-only: runs `git status --porcelain` and `git diff` only. No mutation.

set -u

print_usage() {
    cat >&2 <<'EOF'
Usage:
  pre-archive-check.sh REPO_PATH [REPO_PATH...]
  pre-archive-check.sh --task-id <ID> --shared <REPO_PATH>

Legacy mode: every REPO_PATH must be fully clean.
Shared mode: classify hunks by task ID; only own/mixed/unattributed block.

Exit codes:
  0 - archive may proceed
  1 - archive blocked (dirty / own-task hunks / unattributed)
  2 - usage error
EOF
}

# ---------- Flag parsing (TUNE-0044 shared mode) ----------

TASK_ID=""
SHARED_REPO=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --task-id)
            [ "$#" -ge 2 ] || { echo "ERROR: --task-id requires a value" >&2; exit 2; }
            TASK_ID="$2"
            shift 2
            ;;
        --shared)
            [ "$#" -ge 2 ] || { echo "ERROR: --shared requires a path" >&2; exit 2; }
            SHARED_REPO="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        -*)
            echo "ERROR: unknown flag: $1" >&2
            print_usage
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

# ---------- Conditional-shared auto-detect (TUNE-0056) ----------
# When --task-id is given without --shared, and the next positional repo has a
# `.datarim-shared` marker file at its root, route to shared mode automatically.
# Allows framework repos to opt into shared-workspace semantics without a flag.

if [ -n "$TASK_ID" ] && [ -z "$SHARED_REPO" ] && [ "$#" -ge 1 ]; then
    if [ -d "$1" ] && [ -f "$1/.datarim-shared" ]; then
        SHARED_REPO="$1"
        shift
    fi
fi

# ---------- Shared mode ----------

if [ -n "$SHARED_REPO" ]; then
    # Strict regex validation per CLAUDE.md S1: anchored, no metacharacters.
    if ! printf '%s' "$TASK_ID" | grep -qE '^[A-Z]+-[0-9]{4}$'; then
        echo "ERROR: invalid --task-id (expected ^[A-Z]+-[0-9]{4}$): $TASK_ID" >&2
        exit 2
    fi
    if [ -z "$SHARED_REPO" ]; then
        echo "ERROR: --shared <repo> required with --task-id" >&2
        exit 2
    fi
    if [ ! -e "$SHARED_REPO" ]; then
        echo "ERROR: path not found: $SHARED_REPO" >&2
        exit 2
    fi
    if [ ! -d "$SHARED_REPO/.git" ] && ! git -C "$SHARED_REPO" rev-parse --git-dir >/dev/null 2>&1; then
        echo "ERROR: not a git repository: $SHARED_REPO" >&2
        exit 2
    fi

    # Per-file classification.
    block=0
    saw_foreign=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        # `git status --porcelain` format: XY␣<path>. Strip the 3-char prefix.
        file="${line:3}"
        # Untracked files have no staged diff and no HEAD blob; treat the file
        # contents as the diff text to scan for IDs.
        diff_text=""
        if [ -f "$SHARED_REPO/$file" ]; then
            diff_text="$diff_text"$'\n'"$(cat "$SHARED_REPO/$file" 2>/dev/null || true)"
        fi
        diff_text="$diff_text"$'\n'"$(git -C "$SHARED_REPO" diff -- "$file" 2>/dev/null || true)"
        diff_text="$diff_text"$'\n'"$(git -C "$SHARED_REPO" diff --cached -- "$file" 2>/dev/null || true)"
        found_ids=$(printf '%s' "$diff_text" | grep -oE '[A-Z]+-[0-9]{4}' | sort -u | tr '\n' ',' | sed 's/,$//')
        if [ -z "$found_ids" ]; then
            klass="unattributed"
            block=1
        elif printf ',%s,' "$found_ids" | grep -q ",$TASK_ID,"; then
            if [ "$found_ids" = "$TASK_ID" ]; then
                klass="own"
            else
                klass="mixed"
            fi
            block=1
        else
            klass="foreign"
            saw_foreign=1
        fi
        printf '%s\t%s\t%s\n' "$file" "$klass" "$found_ids"
    done < <(git -C "$SHARED_REPO" status --porcelain 2>/dev/null)

    if [ "$block" -eq 0 ]; then
        if [ "$saw_foreign" -eq 1 ]; then
            echo "OK: shared repo has foreign-only hunks — archive may proceed" >&2
        else
            echo "OK: shared repo clean — archive may proceed" >&2
        fi
        exit 0
    fi

    {
        echo ""
        echo "BLOCKED: shared repo has own / mixed / unattributed hunks for $TASK_ID."
        echo "Apply patch-staging recipe before commit:"
        echo "  - Interactive (TTY): git -C $SHARED_REPO add -p <file>"
        echo "  - Non-interactive (AI agent): blob-swap recipe."
        echo "See commands/dr-archive.md Step 0.1.3 for the canonical recipe."
    } >&2
    exit 1
fi

# ---------- Legacy mode (TUNE-0003) ----------

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
