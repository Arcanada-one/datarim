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
  pre-archive-check.sh --task-id <ID> --shared <REPO_PATH> [--no-whitelist]
                       [--no-schema-check]

Legacy mode: every REPO_PATH must be fully clean.
Shared mode: classify hunks by task ID; only own/mixed/unattributed block.
  Whitelist: version-bump basenames (VERSION, CHANGELOG.md, package.json,
  Cargo.toml, pyproject.toml, .gitignore) bypass default-deny when --task-id
  is set. Use --no-whitelist to restore strict default-deny.
Schema check (TUNE-0071): after clean-git classification, every bullet line
  in REPO/datarim/{tasks,backlog}.md must match the canonical thin-index
  regex. Use --no-schema-check to bypass during in-flight migration.

Exit codes:
  0 - archive may proceed
  1 - archive blocked (dirty / own-task hunks / unattributed / schema-violation)
  2 - usage error
EOF
}

# ---------- TUNE-0059 whitelist (version-bump basenames) ----------
#
# Founding incident: TUNE-0056 self-dogfood — `VERSION` (single line `1.18.1`)
# physically cannot carry a task ID and was misclassified as `unattributed`,
# blocking a legitimate release commit. Whitelist activates only when the
# operator supplies `--task-id` (commit-time disposition). `--no-whitelist`
# escape restores strict default-deny for paranoid contexts.

WHITELIST_BASENAMES=(
    "VERSION"
    "CHANGELOG.md"
    "package.json"
    "Cargo.toml"
    "pyproject.toml"
    ".gitignore"
)

# ---------- TUNE-0061 env-var extension (DATARIM_PRE_ARCHIVE_WHITELIST) ----------
#
# Founding incident: TUNE-0060 self-dogfood — `Projects/Websites/datarim.club/
# config.php` is a legitimate Datarim public-surface version-bump file, but the
# basename `config.php` is project-specific and does not belong in the canonical
# hardcoded list shipped to all consumers. The env-var lets each consumer
# extend the whitelist for their own version-bump files without modifying the
# framework. Format: colon-separated basenames (PATH-style). Path components
# rejected (basename match only, no traversal).

if [ -n "${DATARIM_PRE_ARCHIVE_WHITELIST:-}" ]; then
    IFS=':' read -ra _EXTRA_WHITELIST <<< "$DATARIM_PRE_ARCHIVE_WHITELIST"
    for _entry in "${_EXTRA_WHITELIST[@]}"; do
        [ -z "$_entry" ] && continue
        if [ "$_entry" != "$(basename -- "$_entry")" ] || [ "$_entry" != "${_entry#*/}" ]; then
            echo "ERROR: DATARIM_PRE_ARCHIVE_WHITELIST entries must be basenames (no '/'): $_entry" >&2
            exit 2
        fi
        WHITELIST_BASENAMES+=("$_entry")
    done
    unset _EXTRA_WHITELIST _entry
fi

is_whitelisted_path() {
    local fp="$1"
    local bn
    bn="$(basename -- "$fp")"
    for w in "${WHITELIST_BASENAMES[@]}"; do
        [ "$bn" = "$w" ] && return 0
    done
    return 1
}

# ---------- TUNE-0071 schema-compliance gate ----------
#
# After clean-git classification, every bullet line in datarim/{tasks,backlog}.md
# MUST match the canonical thin-index regex defined in skills/datarim-doctor.md.
# Block on first violation with a pointer to /dr-doctor.
#
# Bypass: --no-schema-check (set NO_SCHEMA_CHECK=1) during in-flight migration.
# Auto-skip: if the repo has no datarim/ subdirectory, the gate is a no-op
# (project repos vs. workspace).

# Canonical line regex (single-line, anchored). Status sets:
#   tasks.md   : in_progress|blocked|not_started
#   backlog.md : pending|blocked-pending|cancelled
SCHEMA_TASKS_RE='^- [A-Z]{2,10}-[0-9]{4} · (in_progress|blocked|not_started) · P[0-3] · L[1-4] · .{1,80} → tasks/[A-Z]{2,10}-[0-9]{4}-task-description\.md$'
SCHEMA_BACKLOG_RE='^- [A-Z]{2,10}-[0-9]{4} · (pending|blocked-pending|cancelled) · P[0-3] · L[1-4] · .{1,80} → tasks/[A-Z]{2,10}-[0-9]{4}-task-description\.md$'

# check_schema_compliance REPO_PATH → exit 0 (clean) | 1 (violations printed to stderr)
check_schema_compliance() {
    local repo="$1"
    [ "$NO_SCHEMA_CHECK" -eq 1 ] && return 0
    [ -d "$repo/datarim" ] || return 0

    local violations=0
    local file
    local re
    for file in tasks.md backlog.md; do
        local fp="$repo/datarim/$file"
        [ -f "$fp" ] || continue
        if [ "$file" = "tasks.md" ]; then
            re="$SCHEMA_TASKS_RE"
        else
            re="$SCHEMA_BACKLOG_RE"
        fi
        # Extract candidate bullet lines (any `- PREFIX-NNNN ...` shape).
        # A line is a violation if it starts with `- {PREFIX}-{NNNN}` but does
        # NOT match the canonical thin-index regex. Strip the leading `^`
        # anchor from $re when composing with the `N:` prefix from grep -n.
        local re_no_anchor="${re#^}"
        local bad
        bad=$(grep -nE '^- [A-Z]+-[0-9]+' "$fp" 2>/dev/null \
              | grep -vE "^[0-9]+:$re_no_anchor" || true)
        # Also flag legacy block-style headings (### TASK-ID:).
        local legacy_blocks
        legacy_blocks=$(grep -nE '^### [A-Z]+-[0-9]+:' "$fp" 2>/dev/null || true)
        if [ -n "$bad" ] || [ -n "$legacy_blocks" ]; then
            {
                echo "BLOCK: $fp contains non-compliant lines (run /dr-doctor):"
                [ -n "$bad" ] && printf '%s\n' "$bad" | sed 's/^/  /'
                [ -n "$legacy_blocks" ] && printf '%s\n' "$legacy_blocks" | sed 's/^/  /'
            } >&2
            violations=1
        fi
    done

    # ---------- TUNE-0071 v2 gates (1.19.1) ----------
    # Gate v2-A: forbidden files. progress.md (abolished v1.19.0) and
    # backlog-archive.md (abolished v1.19.1) MUST NOT exist; their data lives
    # in documentation/archive/{area or cancelled}/archive-{ID}.md.
    local forbidden
    for forbidden in progress.md backlog-archive.md; do
        local fp="$repo/datarim/$forbidden"
        if [ -f "$fp" ]; then
            echo "BLOCK: $fp exists — abolished operational file (run /dr-doctor --fix)" >&2
            violations=1
        fi
    done

    # Gate v2-B: forbidden activeContext.md sections. § «Последние завершённые»
    # / § «Last Completed» were retired in v1.19.1 — recency hint is now a
    # runtime computation in /dr-status --recent.
    local active_ctx="$repo/datarim/activeContext.md"
    if [ -f "$active_ctx" ]; then
        local forbidden_sec
        forbidden_sec=$(grep -nE '^## (Последние завершённые|Last Completed)' "$active_ctx" 2>/dev/null || true)
        if [ -n "$forbidden_sec" ]; then
            {
                echo "BLOCK: $active_ctx contains abolished section (run /dr-doctor --fix):"
                printf '%s\n' "$forbidden_sec" | sed 's/^/  /'
            } >&2
            violations=1
        fi

        # Gate v2-C: activeContext.md § Active Tasks must contain only thin
        # one-liner entries matching SCHEMA_TASKS_RE (same as tasks.md). Extract
        # bullets in § Active Tasks section only (until next ## heading).
        local active_block
        active_block=$(awk '
            /^## Active Tasks$/ { in_block=1; next }
            /^## / { in_block=0 }
            in_block && /^- / { print NR":"$0 }
        ' "$active_ctx" 2>/dev/null)
        if [ -n "$active_block" ]; then
            local re_no_anchor="${SCHEMA_TASKS_RE#^}"
            local bad_active
            # Catch any bullet that mentions a TASK-ID — including legacy
            # `- **TASK-ID** (paragraph)` and `- TASK-ID:` block forms — and
            # validate against canonical thin-index regex. Bullets without a
            # TASK-ID are ignored (operator notes, comments).
            bad_active=$(printf '%s\n' "$active_block" \
                | grep -E '^[0-9]+:- .*[A-Z]+-[0-9]+' \
                | grep -vE "^[0-9]+:$re_no_anchor" || true)
            if [ -n "$bad_active" ]; then
                {
                    echo "BLOCK: $active_ctx § Active Tasks contains non-compliant entries (run /dr-doctor --fix):"
                    printf '%s\n' "$bad_active" | sed 's/^/  /'
                } >&2
                violations=1
            fi
        fi
    fi

    [ "$violations" -eq 0 ] && return 0
    {
        echo ""
        echo "Schema-compliance gate failed. Options:"
        echo "  a. Run /dr-doctor --fix    — migrate operational files."
        echo "  b. Re-run with --no-schema-check (in-flight migration only)."
    } >&2
    return 1
}

# ---------- Flag parsing (TUNE-0044 shared mode, TUNE-0059 whitelist escape) ----------

TASK_ID=""
SHARED_REPO=""
NO_WHITELIST=0
NO_SCHEMA_CHECK=0
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
        --no-whitelist)
            NO_WHITELIST=1
            shift
            ;;
        --no-schema-check)
            NO_SCHEMA_CHECK=1
            shift
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
    hit_own=0
    hit_mixed=0
    hit_unattributed=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        # `git status --porcelain` format: XY␣<path>. Strip the 3-char prefix.
        file="${line:3}"
        # TUNE-0060: capture the actual diff (additions/removals) so we can
        # distinguish IDs introduced by THIS edit from IDs that lived in the
        # committed body. Used by mine-by-elimination klass and (TUNE-0084) by
        # the column-3 display itself.
        diff_changes="$(git -C "$SHARED_REPO" diff -- "$file" 2>/dev/null || true)"
        diff_changes_cached="$(git -C "$SHARED_REPO" diff --cached -- "$file" 2>/dev/null || true)"
        # TUNE-0084: column 3 (`found_ids`) is sourced from the uncommitted
        # diff +/- lines only, NOT from the committed body or hunk context.
        # Index files (`tasks.md`, `activeContext.md`, `backlog.md`) by design
        # list every active task ID in their committed body — both body-cat
        # injection (pre-TUNE-0084) and unfiltered diff output (which carries
        # context lines surrounding every hunk) made column 3 misreport the
        # entire roster as if introduced by this edit. Untracked files have no
        # HEAD blob and no diff at all, so for them the full file content IS
        # the change — fall back to body scan.
        if [ -n "$diff_changes" ] || [ -n "$diff_changes_cached" ]; then
            found_ids=$(printf '%s\n%s\n' "$diff_changes" "$diff_changes_cached" \
                | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' \
                | grep -oE '[A-Z]+-[0-9]{4}' | sort -u | tr '\n' ',' | sed 's/,$//')
        elif [ -f "$SHARED_REPO/$file" ]; then
            found_ids=$(cat "$SHARED_REPO/$file" 2>/dev/null \
                | grep -oE '[A-Z]+-[0-9]{4}' | sort -u | tr '\n' ',' | sed 's/,$//')
        else
            found_ids=""
        fi
        # TUNE-0060/TUNE-0084: separate body-scan signal preserved for the
        # mine-by-elimination branch. `found_ids` (column 3 display) is now
        # diff-only, so we cannot reuse it as the body-presence signal.
        if [ -f "$SHARED_REPO/$file" ]; then
            body_ids=$(cat "$SHARED_REPO/$file" 2>/dev/null \
                | grep -oE '[A-Z]+-[0-9]{4}' | sort -u | tr '\n' ',' | sed 's/,$//')
        else
            body_ids=""
        fi
        # TUNE-0060/TUNE-0068: extract task IDs only from actual added/removed
        # lines (those starting with `+` or `-`, excluding the `+++`/`---` file
        # headers). The earlier `^[+-][^+-]` shape rejected legitimate content
        # lines whose first character was `-` or `+` (markdown bullets, diff
        # markers in prose) — observed via TUNE-0068 self-dogfood on workspace
        # `activeContext.md` where `+- **TUNE-0068**` was filtered out.
        diff_line_ids=$(printf '%s\n%s\n' "$diff_changes" "$diff_changes_cached" \
            | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' \
            | grep -oE '[A-Z]+-[0-9]{4}' | sort -u | tr '\n' ',' | sed 's/,$//')
        if [ -z "$found_ids" ] && [ -z "$body_ids" ]; then
            if [ "$NO_WHITELIST" -eq 0 ] && is_whitelisted_path "$file"; then
                klass="whitelisted"
                # Operator-supplied --task-id is the disposition; surface in stdout
                # so the bypass is visible (not silent).
            else
                klass="unattributed"
                block=1
                hit_unattributed=1
            fi
        elif [ -z "$found_ids" ] && [ -n "$body_ids" ]; then
            # TUNE-0084: diff carries no IDs but body has historical IDs. If the
            # operator declared --task-id and an actual diff exists, this is the
            # mine-by-elimination case (TUNE-0060). Otherwise (untracked
            # ad-hoc note with foreign-only body), default-deny applies.
            if [ -n "$TASK_ID" ] \
               && { [ -n "$diff_changes" ] || [ -n "$diff_changes_cached" ]; }; then
                klass="mine-by-elimination"
                saw_foreign=1
            elif [ "$NO_WHITELIST" -eq 0 ] && is_whitelisted_path "$file"; then
                klass="whitelisted"
            else
                klass="unattributed"
                block=1
                hit_unattributed=1
            fi
        elif printf ',%s,' "$diff_line_ids" | grep -q ",$TASK_ID,"; then
            # TUNE-0068: own/mixed gate considers only IDs on actual diff lines
            # (`^[+-][^+-]`). Committed-body and hunk-context IDs no longer
            # taint classification — closes the false-positive `mixed` observed
            # on workspace `tasks.md`/`activeContext.md`/`backlog.md` in the
            # TUNE-0055 + TUNE-0067 archives where TASK_ID lived only in body.
            if [ "$diff_line_ids" = "$TASK_ID" ]; then
                klass="own"
                hit_own=1
            else
                klass="mixed"
                hit_mixed=1
            fi
            block=1
        else
            klass="foreign"
            saw_foreign=1
        fi
        printf '%s\t%s\t%s\n' "$file" "$klass" "$found_ids"
    done < <(git -C "$SHARED_REPO" status --porcelain 2>/dev/null)

    if [ "$block" -eq 0 ]; then
        # Schema-compliance gate (TUNE-0071) runs after clean-git success.
        if ! check_schema_compliance "$SHARED_REPO"; then
            exit 1
        fi
        if [ "$saw_foreign" -eq 1 ]; then
            echo "OK: shared repo has foreign-only hunks — archive may proceed" >&2
        else
            echo "OK: shared repo clean — archive may proceed" >&2
        fi
        exit 0
    fi

    # TUNE-0084: invariant — BLOCKED message ↔ exit 1. Defensive guard catches
    # any future refactor that decouples wording from exit path.
    if [ "$block" -ne 1 ]; then
        echo "ERROR: pre-archive-check internal: BLOCKED branch with block=$block" >&2
        exit 2
    fi
    # TUNE-0084: list only categories actually observed during iteration; the
    # consolidated "own / mixed / unattributed" header lied when only one
    # category fired.
    hit_categories=""
    [ "$hit_own" -eq 1 ]          && hit_categories="${hit_categories:+$hit_categories, }own"
    [ "$hit_mixed" -eq 1 ]        && hit_categories="${hit_categories:+$hit_categories, }mixed"
    [ "$hit_unattributed" -eq 1 ] && hit_categories="${hit_categories:+$hit_categories, }unattributed"
    {
        echo ""
        echo "BLOCKED: shared repo has $hit_categories hunks for $TASK_ID."
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
    # Schema-compliance gate (TUNE-0071): run on every repo that has datarim/.
    for repo in "$@"; do
        if ! check_schema_compliance "$repo"; then
            exit 1
        fi
    done
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
