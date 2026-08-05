#!/usr/bin/env bash
# closure-gate.sh — assert that the work a task claims is actually present in
# canonical `origin/main` before that task may be marked `done`.
#
# Motivation. A sweep on 2026-07-30 found 22 backlog entries reading `done`
# whose work had never left a worktree. Each carried evidence of the form
# "focused bats N/N green @<sha> (worktree ...)" — true statements about a tree
# that no consumer of the framework could reach. A gate written, tested green
# and left on a branch is indistinguishable in effect from a gate never written.
#
# Why this does NOT assert ancestry of the evidence commit. Datarim's `main`
# requires signed commits and merges pull requests by SQUASH. A squash merge
# rewrites the contribution into one new commit, so the branch's own commits are
# never ancestors of `main`. `git merge-base --is-ancestor <evidence> origin/main`
# is therefore false for every CORRECTLY merged task, and a gate built on it
# would fail everything while passing nothing — an acceptance check no correct
# task can satisfy. The same reasoning rules out `git rev-list --count`.
#
# Why this does NOT match commit messages. `git log --grep=<TASK-ID>` is unsound
# in both directions: it misses work that landed without naming its id, and it
# reports work as landed when an unrelated commit merely mentions the id (an
# observed case: `main` carried "... (tracked as TUNE-0321)" while the TUNE-0321
# work was absent).
#
# What it asserts instead — CONTENT reachability, which squash-merge preserves:
#
#   1. Every file the branch ADDS is present in `origin/main`, matched by blob
#      content or by basename (so a landing under a renamed path still passes).
#   2. Every substantive line the branch ADDS to a file that already existed is
#      findable in the `origin/main` tree. This is what catches a branch whose
#      `--diff-filter=A` count is zero because it only modified files — a shape
#      that added-file counting reports as clean while the work is unmerged.
#
#   3. When a task id is supplied, the ledger carries a ROW for that id — a row
#      that STARTS with the id, not merely a line that mentions it. A sweep on
#      2026-07-31 found merged tasks with no ledger row at all: the work landed
#      on `main` while the index that is supposed to account for it never gained
#      an entry, so the task was invisible to every status query. Anchoring
#      matters in both directions — an unanchored `grep <ID>` reports a row as
#      present when some OTHER row merely cites the id ("supersedes TUNE-0541"),
#      which is the same false-clean this gate exists to prevent.
#
# Usage:
#   closure-gate.sh --root <dir> --branch <name> [--task <ID>] [--base <ref>]
#                   [--max-lines <n>] [--ledger <path>]... [--require-ledger]
#                   [--quiet]
#
# Ledger resolution. `--ledger` may be repeated and makes the row check
# MANDATORY (a named ledger that lacks the row fails the gate). With no
# `--ledger`, the default indexes under `--root` are probed and the check is
# skipped-with-a-note when none exist, so the gate stays usable on roots that
# have no Datarim ledger. `--require-ledger` turns that skip into a failure.
#
# Exit codes:
#   0  work is present in the base ref — closure may proceed
#   1  work is absent, or the ledger has no row for the task — not `done`
#   2  usage / environment error (also the fail-closed path when the base ref
#      cannot be resolved: an unresolvable base is never treated as "clean")
#
# Security: S1 strict mode, all expansions quoted, no eval, argv validated.

set -euo pipefail

ROOT="$PWD"
BRANCH=""
TASK=""
BASE="origin/main"
MAX_LINES=400
QUIET=0
LEDGERS=()
REQUIRE_LEDGER=0
DEFAULT_LEDGERS=("datarim/tasks.md" "datarim/backlog.md")

die_usage() { printf 'closure-gate: %s\n' "$1" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --root)      ROOT="${2:-}";      shift 2 || die_usage "--root needs a value" ;;
    --branch)    BRANCH="${2:-}";    shift 2 || die_usage "--branch needs a value" ;;
    --task)      TASK="${2:-}";      shift 2 || die_usage "--task needs a value" ;;
    --base)      BASE="${2:-}";      shift 2 || die_usage "--base needs a value" ;;
    --max-lines) MAX_LINES="${2:-}"; shift 2 || die_usage "--max-lines needs a value" ;;
    --ledger)    LEDGERS+=("${2:-}");  shift 2 || die_usage "--ledger needs a value" ;;
    --require-ledger) REQUIRE_LEDGER=1; shift ;;
    --quiet)     QUIET=1; shift ;;
    -h|--help)   sed -n '2,45p' "$0"; exit 0 ;;
    *)           die_usage "unknown argument: $1" ;;
  esac
done

[ -n "$BRANCH" ] || die_usage "--branch is required"
[ -d "$ROOT" ]   || die_usage "--root is not a directory: $ROOT"
case "$MAX_LINES" in (*[!0-9]*|'') die_usage "--max-lines must be a positive integer" ;; esac

git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die_usage "not a git repository: $ROOT"

# Fail CLOSED: an unresolvable base ref must never read as "everything landed".
git -C "$ROOT" rev-parse --verify --quiet "$BASE" >/dev/null \
  || die_usage "cannot resolve base ref '$BASE' — refusing to certify closure against an unknown base"
git -C "$ROOT" rev-parse --verify --quiet "$BRANCH" >/dev/null \
  || die_usage "cannot resolve branch '$BRANCH'"

MB="$(git -C "$ROOT" merge-base "$BASE" "$BRANCH" 2>/dev/null || true)"
[ -n "$MB" ] || die_usage "no merge base between '$BASE' and '$BRANCH'"

say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

MISSING_FILES=()
MISSING_LINES=()

# ---------------------------------------------------------------------------
# 1. Files the branch ADDS must exist in the base, by blob or by basename.
#
# The base tree is materialised into two lookup files rather than piped into
# `grep -q`. In a pipeline, `grep -q` exits at the first match and closes the
# pipe; when the upstream producer still has more than a pipe buffer left to
# write it dies with SIGPIPE, and `set -o pipefail` then reports a SUCCESSFUL
# match as a failure. That defect reported two genuinely-landed gates as absent
# and is covered by the large-base-tree regression test.
# ---------------------------------------------------------------------------
BASE_BLOBS="$(mktemp)"; BASE_NAMES="$(mktemp)"
trap 'rm -f "$BASE_BLOBS" "$BASE_NAMES" "${CANDIDATES:-}"' EXIT

git -C "$ROOT" ls-tree -r --format='%(objectname)' "$BASE" | sort -u > "$BASE_BLOBS"
git -C "$ROOT" ls-tree -r --name-only "$BASE" > "$BASE_NAMES"

# basename index, so a landing under a renamed directory still matches
BASE_BASENAMES="$(mktemp)"
trap 'rm -f "$BASE_BLOBS" "$BASE_NAMES" "$BASE_BASENAMES" "${CANDIDATES:-}"' EXIT
sed 's|.*/||' "$BASE_NAMES" | sort -u > "$BASE_BASENAMES"

while IFS= read -r path; do
  [ -n "$path" ] || continue
  blob="$(git -C "$ROOT" rev-parse "$BRANCH:$path" 2>/dev/null || true)"
  if [ -n "$blob" ] && grep -qxF -- "$blob" "$BASE_BLOBS"; then
    continue                                   # identical content is in the base
  fi
  if grep -qxF -- "${path##*/}" "$BASE_BASENAMES"; then
    continue                                   # landed under a renamed directory
  fi
  MISSING_FILES+=("$path")
done < <(git -C "$ROOT" diff --diff-filter=A --name-only "$MB..$BRANCH" 2>/dev/null || true)

# ---------------------------------------------------------------------------
# 2. Substantive lines the branch ADDS to pre-existing files must be findable.
# ---------------------------------------------------------------------------
CANDIDATES="$(mktemp)"
trap 'rm -f "$BASE_BLOBS" "$BASE_NAMES" "$BASE_BASENAMES" "$CANDIDATES"' EXIT

while IFS= read -r path; do
  [ -n "$path" ] || continue
  git -C "$ROOT" diff --diff-filter=M -U0 "$MB..$BRANCH" -- "$path" 2>/dev/null \
    | grep '^+' | grep -v '^+++' | sed 's/^+//' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | awk -v p="$path" 'length($0) >= 12 && $0 !~ /^[[:punct:][:space:]]*$/ { print p "\t" $0 }'
done < <(git -C "$ROOT" diff --diff-filter=M --name-only "$MB..$BRANCH" 2>/dev/null || true) \
  | sort -u -t$'\t' -k2 > "$CANDIDATES"

TOTAL_CAND="$(wc -l < "$CANDIDATES" | tr -d ' ')"
CHECKED=0

# `git grep -F` is NOT a safe fixed-string search: it implements -F by wrapping
# the pattern in \Q...\E, so a pattern containing a literal \E terminates the
# quoting early and the remainder is parsed as a regex. Any line mentioning
# e.g. `yii\base\Exception` or `\ErrorException` therefore silently MISSES and
# the gate falsely reports landed work as absent from the base. Reproduction:
#   git grep -qF 'yii\base\Exception' <rev>   -> no match
#   git show <rev>:<path> | grep -qF '...'    -> match
# GNU grep -F has no such escape layer, so read the blob and pipe it instead.
#
# Pass A checks each candidate against its OWN path in the base — one `git show`
# per distinct path, which covers the overwhelmingly common case.
# Pass B takes only the leftovers and makes ONE streaming scan of the whole base
# tree with `grep -F -f`, so a line that landed under a rename or in a different
# file is still found (the behaviour `git grep` used to provide). Batching
# matters: a per-line repo-wide scan is O(lines x files) subprocesses and pushed
# a 60-line / 1161-file worst case past two minutes.
PASS_A_LEFTOVERS="$(mktemp)"
BASE_FILE_CACHE="$(mktemp)"
trap 'rm -f "$BASE_BLOBS" "$BASE_NAMES" "$BASE_BASENAMES" "$CANDIDATES" "$PASS_A_LEFTOVERS" "$BASE_FILE_CACHE"' EXIT

CUR_PATH=""
while IFS=$'\t' read -r path line; do
  [ -n "$line" ] || continue
  if [ "$CHECKED" -ge "$MAX_LINES" ]; then break; fi
  CHECKED=$((CHECKED + 1))
  # candidates are sorted by line, not path, so cache the last blob read
  if [ "$path" != "$CUR_PATH" ]; then
    CUR_PATH="$path"
    git -C "$ROOT" show "$BASE:$path" > "$BASE_FILE_CACHE" 2>/dev/null || : > "$BASE_FILE_CACHE"
  fi
  if ! grep -qF -- "$line" "$BASE_FILE_CACHE"; then
    printf '%s\t%s\n' "$path" "$line" >> "$PASS_A_LEFTOVERS"
  fi
done < "$CANDIDATES"

if [ -s "$PASS_A_LEFTOVERS" ]; then
  # One scan of the entire base tree for every leftover line at once.
  LEFTOVER_PATTERNS="$(mktemp)"
  BASE_CONTENT="$(mktemp)"
  FOUND_PATTERNS="$(mktemp)"
  trap 'rm -f "$BASE_BLOBS" "$BASE_NAMES" "$BASE_BASENAMES" "$CANDIDATES" "$PASS_A_LEFTOVERS" "$BASE_FILE_CACHE" "$LEFTOVER_PATTERNS" "$BASE_CONTENT" "$FOUND_PATTERNS"' EXIT

  cut -f2- < "$PASS_A_LEFTOVERS" | sort -u > "$LEFTOVER_PATTERNS"
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    git -C "$ROOT" show "$BASE:$_p" 2>/dev/null || true
  done < "$BASE_NAMES" > "$BASE_CONTENT"

  # keep only the patterns that DO occur somewhere in the base
  grep -oF -f "$LEFTOVER_PATTERNS" "$BASE_CONTENT" 2>/dev/null | sort -u > "$FOUND_PATTERNS" || : > "$FOUND_PATTERNS"

  while IFS=$'\t' read -r path line; do
    [ -n "$line" ] || continue
    if ! grep -qxF -- "$line" "$FOUND_PATTERNS"; then
      MISSING_LINES+=("$path	$line")
    fi
  done < "$PASS_A_LEFTOVERS"
fi

# ---------------------------------------------------------------------------
# 3. The ledger must carry a ROW for the task id — anchored at the start of the
#    row, so a line that merely CITES the id elsewhere ("supersedes TUNE-0541")
#    never satisfies the check.
#
#    Two row shapes are accepted, matching the schemas the framework has shipped:
#      thin one-liner : "- TUNE-0541 · done · P2 · L2 · <summary> -> <path>"
#      table          : "| TUNE-0541 | ... |"
#    In both, the id must be the first token of the row.
# ---------------------------------------------------------------------------
LEDGER_STATUS="skipped"
LEDGER_FILES_SEEN=()

if [ -n "$TASK" ]; then
    ledger_paths=()
    if [ "${#LEDGERS[@]}" -gt 0 ]; then
        ledger_paths=("${LEDGERS[@]}")
        explicit_ledger=1
    else
        explicit_ledger=0
        for cand in "${DEFAULT_LEDGERS[@]}"; do
            [ -f "$ROOT/$cand" ] && ledger_paths+=("$cand")
        done
    fi

    # An explicitly named ledger that does not exist is an environment error,
    # never a silent pass.
    if [ "$explicit_ledger" -eq 1 ]; then
        for lp in "${ledger_paths[@]}"; do
            case "$lp" in (/*) abs="$lp" ;; (*) abs="$ROOT/$lp" ;; esac
            [ -f "$abs" ] || die_usage "--ledger file not found: $lp"
        done
    fi

    if [ "${#ledger_paths[@]}" -eq 0 ]; then
        if [ "$REQUIRE_LEDGER" -eq 1 ]; then
            LEDGER_STATUS="absent"
        fi
    else
        row_re="^[[:space:]]*([-*][[:space:]]+|\|[[:space:]]*)${TASK}([[:space:]]|\||·|$)"
        LEDGER_STATUS="missing"
        for lp in "${ledger_paths[@]}"; do
            case "$lp" in (/*) abs="$lp" ;; (*) abs="$ROOT/$lp" ;; esac
            LEDGER_FILES_SEEN+=("$lp")
            if grep -qE -- "$row_re" "$abs" 2>/dev/null; then
                LEDGER_STATUS="present"
                break
            fi
        done
    fi
fi

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------
label="${TASK:-$BRANCH}"

ledger_ok=1
case "$LEDGER_STATUS" in
    missing|absent) ledger_ok=0 ;;
esac

if [ "${#MISSING_FILES[@]}" -eq 0 ] && [ "${#MISSING_LINES[@]}" -eq 0 ] && [ "$ledger_ok" -eq 1 ]; then
  say "closure-gate: PASS — all content from '$BRANCH' is present in '$BASE' ($label)"
  case "$LEDGER_STATUS" in
    present) say "closure-gate: ledger row for $TASK found" ;;
    skipped) [ -n "$TASK" ] && say "closure-gate: note — no ledger index found; row check skipped" ;;
  esac
  [ "$TOTAL_CAND" -gt "$CHECKED" ] && \
    say "closure-gate: note — checked $CHECKED of $TOTAL_CAND candidate lines (--max-lines $MAX_LINES)"
  exit 0
fi

if [ "${#MISSING_FILES[@]}" -eq 0 ] && [ "${#MISSING_LINES[@]}" -eq 0 ]; then
    say "closure-gate: FAIL — content from '$BRANCH' is present in '$BASE', but the"
    say "closure-gate: ledger has no row for $label."
else
    say "closure-gate: FAIL — work claimed by $label is NOT present in '$BASE'."
fi
say "closure-gate: this task must not be marked \`done\`."
say ""

if [ "$ledger_ok" -eq 0 ]; then
    if [ "$LEDGER_STATUS" = "absent" ]; then
        say "Ledger: no index found under '$ROOT' (--require-ledger was given)."
        say "  looked for: ${DEFAULT_LEDGERS[*]}"
    else
        say "Ledger: no row STARTING with '$TASK' in:"
        for lp in "${LEDGER_FILES_SEEN[@]}"; do say "  $lp"; done
        say "  A line that merely mentions '$TASK' inside another row does not count —"
        say "  the id must be the first token of its own row."
    fi
    say ""
fi

if [ "${#MISSING_FILES[@]}" -gt 0 ]; then
  say "Files added on '$BRANCH' and absent from '$BASE' (${#MISSING_FILES[@]}):"
  for f in "${MISSING_FILES[@]}"; do say "  $f"; done
  say ""
fi

if [ "${#MISSING_LINES[@]}" -gt 0 ]; then
  say "Lines added to pre-existing files and absent from '$BASE' (${#MISSING_LINES[@]}):"
  n=0
  for entry in "${MISSING_LINES[@]}"; do
    n=$((n + 1)); [ "$n" -gt 20 ] && { say "  ... and $(( ${#MISSING_LINES[@]} - 20 )) more"; break; }
    say "  ${entry%%	*}: $(printf '%s' "${entry#*	}" | cut -c1-100)"
  done
  say ""
fi

if [ "$TOTAL_CAND" -gt "$CHECKED" ]; then
  say "closure-gate: note — checked $CHECKED of $TOTAL_CAND candidate lines (--max-lines $MAX_LINES);"
  say "              the reported set is therefore a lower bound, not the full residue."
fi

exit 1
