#!/usr/bin/env bash
# check-archive-landing.sh — archive-vs-reality landing verifier (TUNE-0562).
#
# An archive doc that names an artefact path or a commit SHA is treated by
# readers, by the backlog and by later tasks as proof the work shipped. It is
# not. The failure mode: a task finishes on a feature branch, the archive is
# written recording the SHA and artefact list, the branch is then tagged
# `zz-archived/<name>` or deleted WITHOUT being merged — and nothing detects it.
# The backlog row goes `done` and the archive reads as authoritative.
#
# Measured 2026-08-02 across 231 framework archives: four tasks declared
# completed work absent from the shipped tree. TUNE-0334 (regex fix + 13-case
# suite) survived only as `zz-archived/feat/tune-0334-snapshot-id-regex`, so
# stage-snapshot and `/dr-next` resume stayed silently broken for every
# slug-suffix follow-up ID for six weeks after the archive said otherwise.
# TUNE-0167 (22 files / +2071 lines) and TUNE-0294 (8 artefacts) were absent
# from the target ref but remained preserved in linked worktrees. An earlier
# audit missed those worktree HEADs and incorrectly described the work as lost.
#
# Two directions, deliberately weighted differently:
#
#   A (blocking)  an archive claims an artefact path or SHA -> assert the path
#                 exists on the ref and the SHA is reachable from it. A false
#                 claim of completion is the expensive direction: it stops
#                 anyone from ever looking again.
#
#   B (advisory)  a pending/in_progress backlog row names an artefact path that
#                 ALREADY exists on the ref -> report as a stale-label candidate.
#                 Heuristic by construction: a path existing does not prove the
#                 row's intent was met, so this NEVER fails the build. It is a
#                 worklist for a human, not a verdict.
#
# METHOD — judge by CONTENT, never by ancestry. `git cat-file -e <ref>:<path>`
# and `git diff --diff-filter=A --name-only`. Squash-merge rewrites commits, so
# `git rev-list --count <ref>..<branch>` lies in BOTH directions: a branch can
# report "6 commits ahead" while being behind by content. Every landing check
# here asks the object store what exists, not what descends from what.
#
# A SHA is "reachable" if `git merge-base --is-ancestor <sha> <ref>` succeeds.
# An unknown SHA (absent from the object store entirely) is reported distinctly
# from a known-but-unreachable one. For a known adrift commit, the verifier also
# reports whether all refs, a linked worktree HEAD, or only the loose object
# preserves it. Landing on the target ref and preservation elsewhere are
# separate facts and need separate responses.
#
# API:
#   check-archive-landing.sh [--root <repo>] [--ref <ref>] [--archives <dir>]
#                            [--backlog <file>] [--direction a|b|both]
#                            [--report] [--quiet]
#     --root       repo root (default: script-dir/..)
#     --ref        ref to verify against (default: origin/main, falls back to HEAD)
#     --archives   archive dir. Point this at the subdir whose artefacts belong to
#                  --root, NOT at the whole archive tree: archives are filed per
#                  project (`framework/`, `adsessor/`, `agents/`, ...) and each
#                  project's artefacts live in ITS OWN repo. Verifying an
#                  `adsessor/` archive against the framework repo reports every
#                  path as missing — 2865 "violations" in one measured run, all
#                  noise. A gate that cries wolf at that volume is not a gate.
#     --backlog    backlog file for direction B (default: <root>/datarim/backlog.md)
#     --since      only check archives whose completed_date is >= this ISO date
#                  (default: the baseline below). See § Baseline.
#     --direction  which direction to run (default: both)
#     --report     human-readable findings (default: summary only)
#     --quiet      suppress per-finding output; exit code only
#
# Exit codes:
#   0 — clean (no direction-A violations; advisory B findings do not fail)
#   1 — at least one direction-A violation
#   2 — usage error
#   3 — root/ref not usable
#
# § Baseline — why this gate does not judge the whole back-catalogue
#
# Running direction A over all 235 framework archives yields 211 "violations"
# that are almost entirely legitimate history, not lost work:
#   * `docs/` -> `documentation/` (Diátaxis migration) moved ~98 files;
#   * flat skills became directories (`skills/foo.md` -> `skills/foo/SKILL.md`);
#   * genuinely obsolete scripts (`scripts/check-drift.sh`) were deleted on purpose;
#   * 171 cited SHAs predate the 2026-05-19 history rewrite and cannot resolve.
#
# None of that is distinguishable from real loss by inspecting a path alone, and
# a gate that reports 211 findings where ~4 are real trains everyone to ignore
# it — the exact failure this task exists to fix. So the gate is a RATCHET: it
# verifies archives written from the baseline date onward, where "the artefact
# path in the archive should still resolve" is a fair contract. History before
# that is swept once, by hand, and recorded — not re-litigated on every CI run.
#
# Move the baseline forward only; never backward to silence a real finding.
#
# Read-only: no writes, no network. Requires: bash, git, grep, sed.

set -uo pipefail

SCRIPT_NAME="check-archive-landing.sh"
ROOT=""
REF=""
ARCHIVE_DIR=""
BACKLOG=""
DIRECTION="both"
REPORT=0
QUIET=0
SCOPE_GUARD=1
# Thresholds for the cross-repo scope guard (see run_direction_a). The floor on
# claim count keeps a tiny fixture from tripping it; the percentage is set well
# above any plausible real-world breakage — the measured wrong-repo run was 87%.
SCOPE_GUARD_PCT=60
SCOPE_GUARD_MIN_CLAIMS=50
# Ratchet baseline (see § Baseline). Archives completed before this date are not
# judged: their paths predate the docs/ and skills/ restructures and the history
# rewrite, so a failure there says nothing about landing.
SINCE="2026-07-01"

print_usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--root <repo>] [--ref <ref>] [--archives <dir>]
                    [--backlog <file>] [--direction a|b|both] [--report] [--quiet]

  A (blocking) archives claiming artefacts/SHAs that never landed
  B (advisory) pending backlog rows whose artefact already exists

Exit: 0 clean | 1 direction-A violation | 2 usage | 3 root/ref unusable
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --root)      ROOT="${2:-}"; shift 2 ;;
        --ref)       REF="${2:-}"; shift 2 ;;
        --archives)  ARCHIVE_DIR="${2:-}"; shift 2 ;;
        --backlog)   BACKLOG="${2:-}"; shift 2 ;;
        --since)     SINCE="${2:-}"; shift 2 ;;
        --direction) DIRECTION="${2:-}"; shift 2 ;;
        --report)    REPORT=1; shift ;;
        --quiet)     QUIET=1; shift ;;
        --no-scope-guard) SCOPE_GUARD=0; shift ;;
        -h|--help)   print_usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; print_usage >&2; exit 2 ;;
    esac
done

case "$DIRECTION" in
    a|b|both) ;;
    *) echo "ERROR: --direction must be a, b or both" >&2; exit 2 ;;
esac

if [ -z "$ROOT" ]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
[ -d "$ROOT/.git" ] || [ -f "$ROOT/.git" ] || {
    echo "ERROR: not a git repo: $ROOT" >&2; exit 3; }

# Default ref is origin/main — the shipped surface. A local checkout may carry
# unmerged work, so verifying against HEAD would call unlanded artefacts landed;
# HEAD is only a fallback for clones with no origin (CI shallow checkouts, forks).
if [ -z "$REF" ]; then
    if git -C "$ROOT" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
        REF="origin/main"
    else
        REF="HEAD"
    fi
fi
git -C "$ROOT" rev-parse --verify --quiet "$REF" >/dev/null 2>&1 || {
    echo "ERROR: ref not resolvable: $REF" >&2; exit 3; }

# The framework repo ships no archives of its own — they live in the consuming
# workspace. Accept either layout so the gate is usable from both.
if [ -z "$ARCHIVE_DIR" ]; then
    if [ -d "$ROOT/documentation/archive" ]; then
        ARCHIVE_DIR="$ROOT/documentation/archive"
    fi
fi
[ -n "$BACKLOG" ] || BACKLOG="$ROOT/datarim/backlog.md"

VIOLATIONS=0
ADVISORIES=0
ARCHIVES_SCANNED=0
CLAIMS_CHECKED=0
UNVERIFIABLE=0
FOREIGN=0
MOVED=0
UNDATED=0
PRE_BASELINE=0
SQUASHED=0

emit() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$1"; }

# Does <path> exist on the ref? Content question, not an ancestry question.
path_on_ref() {  # $1=path
    git -C "$ROOT" cat-file -e "${REF}:$1" 2>/dev/null
}

# Classify a SHA: reachable | unreachable | unknown.
#
# "unknown" (not in the object store at all) and "unreachable" (present but not
# an ancestor) are NOT the same finding. Unknown means the work may be gone
# entirely — check every clone, reflog and `git fsck --lost-found` before
# declaring loss. Unreachable means it exists and simply never merged, which is
# recoverable by relanding.
sha_status() {  # $1=sha
    local sha="$1"
    if ! git -C "$ROOT" cat-file -e "${sha}^{commit}" 2>/dev/null; then
        echo "unknown"; return
    fi
    if git -C "$ROOT" merge-base --is-ancestor "$sha" "$REF" 2>/dev/null; then
        echo "reachable"
    else
        echo "unreachable"
    fi
}

# List every ref whose tip contains <sha>. `for-each-ref` without a prefix
# searches the complete refs namespace (local branches, remote-tracking refs,
# tags and archival refs), not just the currently checked-out branch.
refs_containing_sha() {  # $1=sha
    git -C "$ROOT" for-each-ref --contains "$1" --format='%(refname)' 2>/dev/null \
        | sort -u
}

# List every linked-worktree HEAD that contains <sha>. Detached worktree HEADs
# have no ref and are therefore invisible to refs_containing_sha. Compare by
# ancestry rather than equality because a worktree may have advanced since the
# archived commit while still preserving it. Paths are deliberately not
# emitted: preservation is the useful public diagnostic, not a host-local path.
worktree_heads_containing_sha() {  # $1=sha
    local sha="$1" line head_sha=""

    while IFS= read -r line; do
        case "$line" in
            "HEAD "*) head_sha="${line#HEAD }" ;;
            "")
                if [ -n "$head_sha" ] \
                    && git -C "$ROOT" merge-base --is-ancestor "$sha" "$head_sha" 2>/dev/null; then
                    printf '%s\n' "$head_sha"
                fi
                head_sha=""
                ;;
        esac
    done < <(git -C "$ROOT" worktree list --porcelain 2>/dev/null; printf '\n') \
        | sort -u
}

# A landing violation says only that work is absent from the target ref. Before
# an operator decides how to recover it, report every bounded preservation
# surface available in this repository. A commit with no containing ref or
# worktree is OBJECT-ONLY, not "unrecoverable": the object still exists today.
emit_sha_preservation() {  # $1=archive name  $2=sha
    local doc_name="$1" sha="$2" refs worktree_heads found=0 ref_name head_sha

    refs="$(refs_containing_sha "$sha")"
    if [ -n "$refs" ]; then
        while IFS= read -r ref_name; do
            [ -n "$ref_name" ] || continue
            emit "RECOVERABLE-REF    $doc_name  cites \`$sha\` — preserved by ref \`$ref_name\`; absent from target ref $REF"
            found=1
        done <<< "$refs"
    fi

    worktree_heads="$(worktree_heads_containing_sha "$sha")"
    if [ -n "$worktree_heads" ]; then
        while IFS= read -r head_sha; do
            [ -n "$head_sha" ] || continue
            emit "RECOVERABLE-WORKTREE  $doc_name  cites \`$sha\` — preserved by linked worktree HEAD \`$head_sha\`; absent from target ref $REF"
            found=1
        done <<< "$worktree_heads"
    fi

    if [ "$found" -eq 0 ]; then
        emit "OBJECT-ONLY        $doc_name  cites \`$sha\` — commit object exists, but no ref or linked worktree HEAD contains it; absent from target ref $REF"
    fi
}

# Extract backtick-quoted repo-relative artefact paths from a markdown file.
#
# Only paths under known shipped roots are considered: an archive is prose and
# mentions plenty of things that are not deliverables (URLs, other repos,
# illustrative names). Anchoring to real top-level dirs keeps the false-positive
# rate low enough that a red gate means something.
extract_paths() {  # $1=file
    grep -oE '`(commands|skills|agents|templates|scripts|dev-tools|tests|cli|plugins|docs|documentation)/[A-Za-z0-9._/-]+`' "$1" 2>/dev/null \
        | tr -d '`' \
        | grep -vE '/$' \
        | sort -u
}

# Extract 7-40 hex commit SHAs cited in backticks.
#
# The `[0-9a-f]` class alone matches plenty of non-SHA hex (checksums, ids), so
# require a backtick delimiter and a length in git's range, then let
# `cat-file -e` be the real filter — a false candidate simply resolves to
# "unknown" and is reported as unverifiable rather than as a loss.
extract_shas() {  # $1=file
    grep -oE '`[0-9a-f]{7,40}`' "$1" 2>/dev/null \
        | tr -d '`' \
        | sort -u
}

# ---------------- direction A: archives must tell the truth ----------------
run_direction_a() {
    [ -n "$ARCHIVE_DIR" ] && [ -d "$ARCHIVE_DIR" ] || {
        emit "SKIP: no archive dir found (looked for <root>/documentation/archive)"
        return 0
    }

    while IFS= read -r doc; do
        [ -n "$doc" ] || continue
        doc_name="$(basename "$doc")"

        # Ratchet: skip anything completed before the baseline. An archive with no
        # parseable date is SKIPPED, not judged — most undated archives are the
        # oldest ones, and guessing would reintroduce exactly the false-positive
        # flood the baseline exists to prevent. Undated archives are counted so the
        # summary never implies coverage the run did not have.
        adate="$(grep -m1 -oE '^completed_date: *[0-9]{4}-[0-9]{2}-[0-9]{2}' "$doc" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')"
        if [ -z "$adate" ]; then
            UNDATED=$((UNDATED + 1))
            continue
        fi
        if [ "$adate" \< "$SINCE" ]; then
            PRE_BASELINE=$((PRE_BASELINE + 1))
            continue
        fi

        ARCHIVES_SCANNED=$((ARCHIVES_SCANNED + 1))

        while IFS= read -r p; do
            [ -n "$p" ] || continue
            CLAIMS_CHECKED=$((CLAIMS_CHECKED + 1))
            if ! path_on_ref "$p"; then
                # Distinguish deleted-since from never-existed. A path that once
                # existed and is now gone is a real signal — the work landed and
                # was later removed, which the archive should have recorded. A
                # path with NO history in this repo at all is almost always an
                # artefact of a different repo (ROB-0001's `docs/AER-*.md` live in
                # the Rules-of-Robotics repo but its archive is filed under
                # framework/), so it says nothing about this repo's landing state.
                if git -C "$ROOT" log --all --oneline --diff-filter=A -- "$p" 2>/dev/null | grep -q .; then
                    # Renames are not losses. A file that moved still ships; the
                    # archive's path is merely stale. `docs/` -> `documentation/`
                    # (the Diátaxis migration) alone accounted for most of the
                    # 230 "removed" artefacts in a measured run. Look for a
                    # surviving file of the same basename before crying loss.
                    # NOTE: `git ls-tree | grep -q` is WRONG under `pipefail`.
                    # grep -q exits on first match, git gets SIGPIPE, and pipefail
                    # propagates that failure — so the match silently reads as "no
                    # match" and every moved file is misreported as removed. Count
                    # instead: grep consumes the whole stream, so no SIGPIPE.
                    base="$(basename "$p")"
                    hits="$(git -C "$ROOT" ls-tree -r --name-only "$REF" 2>/dev/null \
                        | grep -cE "(^|/)${base//./\\.}$" || true)"

                    # Second rename shape: a flat page became a directory with a
                    # canonical filename inside — `skills/testing.md` is now
                    # `skills/testing/SKILL.md`. The basename changes, so the
                    # check above cannot see it; without this, the whole
                    # skills-flattening migration reads as deletion (7 of
                    # TUNE-0253's findings alone).
                    if [ "${hits:-0}" -eq 0 ]; then
                        stem="${p%.md}"
                        if [ "$stem" != "$p" ] && path_on_ref "$stem/SKILL.md"; then
                            hits=1
                        fi
                    fi

                    if [ "${hits:-0}" -gt 0 ]; then
                        MOVED=$((MOVED + 1))
                        [ "$REPORT" -eq 1 ] && emit "MOVED-ARTEFACT    $doc_name  claims \`$p\` — not at that path, but \`$base\` still ships (stale path in archive)"
                    else
                        VIOLATIONS=$((VIOLATIONS + 1))
                        emit "REMOVED-ARTEFACT  $doc_name  claims \`$p\` — existed once, but no file of that name exists on target ref $REF (target-ref finding only)"
                    fi
                else
                    FOREIGN=$((FOREIGN + 1))
                    [ "$REPORT" -eq 1 ] && emit "FOREIGN-ARTEFACT  $doc_name  claims \`$p\` — no history in this repo (likely another repo's artefact)"
                fi
            fi
        done < <(extract_paths "$doc")

        while IFS= read -r s; do
            [ -n "$s" ] || continue
            CLAIMS_CHECKED=$((CLAIMS_CHECKED + 1))
            case "$(sha_status "$s")" in
                reachable) ;;
                unreachable)
                    # An unreachable SHA is NOT by itself a violation. Squash-merge
                    # is the norm in this repo, and squashing rewrites the commit:
                    # the branch's original SHAs never become ancestors of main
                    # even though every byte of their content landed. TUNE-0210's
                    # five "unmerged" commits are exactly this — both artefacts
                    # ship on main today.
                    #
                    # So ask the only question that matters: did this commit's
                    # FILES land? If every path it touched exists on the ref, the
                    # work shipped under a different SHA and there is nothing to
                    # report. If none of them did, the work is genuinely adrift —
                    # which is precisely how TUNE-0334 hid for six weeks.
                    touched=0; present=0
                    while IFS= read -r tp; do
                        [ -n "$tp" ] || continue
                        touched=$((touched + 1))
                        if path_on_ref "$tp"; then
                            present=$((present + 1))
                        else
                            # Same flattening as above: a commit touching
                            # `skills/testing.md` looks adrift once that page
                            # became `skills/testing/SKILL.md`, though its content
                            # ships. Both remaining ADRIFT findings in the sweep
                            # were this, not lost work.
                            tstem="${tp%.md}"
                            if [ "$tstem" != "$tp" ] && path_on_ref "$tstem/SKILL.md"; then
                                present=$((present + 1))
                            fi
                        fi
                    done < <(git -C "$ROOT" show --pretty=format: --name-only "$s" 2>/dev/null | grep -v '^$' | sort -u)

                    if [ "$touched" -eq 0 ]; then
                        UNVERIFIABLE=$((UNVERIFIABLE + 1))
                        [ "$REPORT" -eq 1 ] && emit "UNVERIFIABLE-SHA  $doc_name  cites \`$s\` — not an ancestor of $REF and touched no resolvable paths"
                    elif [ "$present" -eq 0 ]; then
                        VIOLATIONS=$((VIOLATIONS + 1))
                        emit "ADRIFT-SHA        $doc_name  cites \`$s\` — not an ancestor of target ref $REF and NONE of its $touched file(s) exist there (landing violation)"
                        emit_sha_preservation "$doc_name" "$s"
                    else
                        SQUASHED=$((SQUASHED + 1))
                        [ "$REPORT" -eq 1 ] && emit "SQUASHED-SHA      $doc_name  cites \`$s\` — not an ancestor, but $present/$touched of its files ship on $REF (landed under a squash)"
                    fi
                    ;;
                unknown)
                    # NOT a violation. A SHA absent from the object store does not
                    # prove the work was lost: this repo's history was force-rewritten
                    # on 2026-05-19 (credential scrub), so every pre-rewrite SHA an
                    # older archive cites is unresolvable BY CONSTRUCTION — 171 of
                    # them in one measured run, all from the April/May TUNE-0003..0100
                    # era, none actually missing work. Treating those as failures
                    # would make the gate permanently red and therefore ignored.
                    # Reported as unverifiable so a human can check the clones,
                    # reflog and `git fsck` where it matters.
                    UNVERIFIABLE=$((UNVERIFIABLE + 1))
                    [ "$REPORT" -eq 1 ] && emit "UNVERIFIABLE-SHA  $doc_name  cites \`$s\` — not in this object store; preservation and landing on target ref $REF cannot be verified from this repository"
                    ;;
            esac
        done < <(extract_shas "$doc")
    done < <(find "$ARCHIVE_DIR" -type f -name 'archive-*.md' 2>/dev/null | sort)

    # Scope guard. If nearly every claim looks missing, the overwhelmingly likely
    # cause is that --archives points at another project's archives, not that the
    # repo lost almost everything it ever shipped. Refuse the verdict rather than
    # emit a wall of false positives: an unusable gate gets disabled, and a
    # disabled gate is the state this whole task exists to fix.
    if [ "$SCOPE_GUARD" -eq 1 ] && [ "$CLAIMS_CHECKED" -ge "$SCOPE_GUARD_MIN_CLAIMS" ]; then
        local pct=$(( VIOLATIONS * 100 / CLAIMS_CHECKED ))
        if [ "$pct" -ge "$SCOPE_GUARD_PCT" ]; then
            echo "ERROR: ${pct}% of ${CLAIMS_CHECKED} claims failed — this almost certainly means" >&2
            echo "       --archives is pointed at archives whose artefacts live in a DIFFERENT repo" >&2
            echo "       than --root ($ROOT). Archives are filed per project; point --archives at the" >&2
            echo "       subdir matching this repo (e.g. documentation/archive/framework)." >&2
            echo "       Refusing to report a verdict. Override with --no-scope-guard if intended." >&2
            exit 3
        fi
    fi
}

# ------------- direction B: pending rows whose work already exists -------------
run_direction_b() {
    [ -f "$BACKLOG" ] || {
        emit "SKIP: no backlog at $BACKLOG"
        return 0
    }

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        id="$(printf '%s' "$line" | grep -oE '^- [A-Z][A-Z0-9]*-[0-9]+' | sed 's/^- //')"
        [ -n "$id" ] || continue

        present=""
        while IFS= read -r p; do
            [ -n "$p" ] || continue
            if path_on_ref "$p"; then
                present="${present}${present:+, }$p"
            fi
        done < <(printf '%s\n' "$line" \
            | grep -oE '`(commands|skills|agents|templates|scripts|dev-tools|tests|cli|plugins)/[A-Za-z0-9._/-]+`' \
            | tr -d '`' | sort -u)

        if [ -n "$present" ]; then
            ADVISORIES=$((ADVISORIES + 1))
            emit "STALE-LABEL?      $id  is open, but already on $REF: $present"
        fi
    done < <(grep -E '^- [A-Z][A-Z0-9]*-[0-9]+ . (pending|in_progress)' "$BACKLOG" 2>/dev/null)
}

[ "$DIRECTION" = "a" ] || [ "$DIRECTION" = "both" ] && run_direction_a
[ "$DIRECTION" = "b" ] || [ "$DIRECTION" = "both" ] && run_direction_b

if [ "$REPORT" -eq 1 ] || [ "$QUIET" -eq 0 ]; then
    echo "=== Summary ==="
    echo "ref=$REF  since=$SINCE  archives-judged=$ARCHIVES_SCANNED  claims-checked=$CLAIMS_CHECKED"
    echo "skipped: $PRE_BASELINE pre-baseline, $UNDATED undated (no completed_date)"
    echo "direction-A violations: $VIOLATIONS (blocking)"
    echo "direction-B advisories: $ADVISORIES (informational — never fails)"
    echo "unverifiable SHAs:      $UNVERIFIABLE (pre-rewrite history, or lost — --report to list)"
    echo "foreign artefacts:      $FOREIGN (no history here; another repo's — --report to list)"
    echo "moved artefacts:        $MOVED (still ship under a new path — --report to list)"
    echo "squash-landed SHAs:     $SQUASHED (not ancestors, but their files ship — --report to list)"
    if [ "$VIOLATIONS" -eq 0 ]; then
        echo "RESULT: PASS"
    else
        echo "RESULT: FAIL"
    fi
fi

[ "$VIOLATIONS" -gt 0 ] && exit 1
exit 0
