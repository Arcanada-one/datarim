#!/usr/bin/env bash
#
# release-ledger-report.sh — reconcile the CHANGELOG release ledger against git history.
#
# TARGET SCOPE
#   Answers one question with evidence: for every commit that landed between the
#   last CHANGELOG-documented release and HEAD, which version section does it
#   belong to — and is any commit left unclassified (an "orphan")?
#
# WHY THIS EXISTS
#   The repo bumps its version in the CLAUDE.md header (and, since the VERSION
#   file was introduced, there too) but did not always cut a matching CHANGELOG
#   section. That lets VERSION and CHANGELOG drift by several releases. This
#   script reconstructs the true per-version commit boundaries from the version
#   header's own history, so the ledger can be rebuilt from evidence rather than
#   from memory.
#
# METHOD (no magic constants — boundaries are derived, not hardcoded)
#   1. Walk every commit that touched CLAUDE.md, in chronological order.
#   2. Read the declared version at each such commit.
#   3. A commit where the declared version CHANGES is that version's boundary
#      (its "cut" commit).
#   4. Version section X = commits in (cut of previous version, cut of X].
#      Lower bound exclusive, upper bound inclusive: a change that lands after
#      version N is cut ships in version N+1, and the cut commit itself carries
#      the feature it bumps for (this repo's squash-merge convention).
#   5. Ranges are asserted to partition the full commit set exactly — that is the
#      zero-orphan proof.
#
# MODES
#   --check    exit 0 = ledger reconcilable with zero orphans, exit 1 = orphans found
#   --report   human-readable per-version commit/PR mapping (implies the check)
#   --bullets  map each CHANGELOG [Unreleased] bullet to its true version section
#
# Requires: git, awk, sed. No other dependencies.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

CHANGELOG="CHANGELOG.md"
MODE="--report"
[ $# -gt 0 ] && MODE="$1"

# ---------------------------------------------------------------------------
# Step 1 — collect the versions that already have a CHANGELOG section.
# ---------------------------------------------------------------------------
documented="$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$CHANGELOG" | tr -d '#[] ')"

if [ -z "$documented" ]; then
    echo "ERROR: no released version section found in $CHANGELOG" >&2
    exit 2
fi

is_documented() {
    printf '%s\n' "$documented" | grep -qx -- "$1"
}

# ---------------------------------------------------------------------------
# Step 2 — derive version boundaries from the CLAUDE.md version header history.
# ---------------------------------------------------------------------------
version_at() {
    # Declared version at a given commit; empty if the header is absent there.
    git show "$1:CLAUDE.md" 2>/dev/null \
        | sed -n 's/^> \*\*Version:\*\* *//p' | head -1 | tr -d '[:space:]'
}

boundaries=""   # newline-separated "version<TAB>sha", chronological
prev_version=""
while read -r sha; do
    [ -z "$sha" ] && continue
    v="$(version_at "$sha")"
    [ -z "$v" ] && continue
    if [ "$v" != "$prev_version" ]; then
        boundaries="${boundaries}${v}	${sha}
"
        prev_version="$v"
    fi
done <<EOF
$(git log --reverse --format='%H' -- CLAUDE.md)
EOF

if [ -z "$boundaries" ]; then
    echo "ERROR: could not derive any version boundary from CLAUDE.md history" >&2
    exit 2
fi

cut_of() {
    printf '%s' "$boundaries" | awk -F'\t' -v v="$1" '$1==v {print $2; exit}'
}

# The reconciliation base is the NEWEST version that is both documented in the
# CHANGELOG and has a derivable boundary commit. A version documented but not yet
# boundaried is the release being cut right now (its bump is still uncommitted) —
# it is handled as the trailing open range, not as the base.
last_documented=""
while IFS= read -r bline; do
    [ -z "$bline" ] && continue
    bv="${bline%%	*}"
    if is_documented "$bv"; then
        last_documented="$bv"
    fi
done <<EOF
$boundaries
EOF

if [ -z "$last_documented" ]; then
    echo "ERROR: no version is both documented in $CHANGELOG and boundaried in history" >&2
    exit 2
fi
base_sha="$(cut_of "$last_documented")"

# Versions strictly newer than the base, in order.
pending_versions="$(printf '%s' "$boundaries" | awk -F'\t' -v base="$last_documented" '
    found { print $1 }
    $1 == base { found = 1 }
')"

# ---------------------------------------------------------------------------
# Ledger-drift check — the regression guard for the defect this tool was built
# for: a version bumped in the header but never cut as a CHANGELOG section.
# ---------------------------------------------------------------------------
undocumented=""
for v in $pending_versions; do
    is_documented "$v" || undocumented="${undocumented}${v} "
done

# The in-flight version (HEAD is past the newest cut) is handled as a trailing
# open range below.
head_version="$(version_at HEAD)"

total_commits="$(git rev-list --count "${base_sha}..HEAD")"

# ---------------------------------------------------------------------------
# Step 3 — assign every commit to exactly one version section.
# ---------------------------------------------------------------------------
assigned=0
range_lower="$base_sha"
report=""
for v in $pending_versions; do
    upper="$(cut_of "$v")"
    n="$(git rev-list --count "${range_lower}..${upper}")"
    assigned=$((assigned + n))
    report="${report}${v}	${range_lower}..${upper}	${n}
"
    range_lower="$upper"
done

# Trailing open range: commits after the newest cut are the next, uncut release.
trailing="$(git rev-list --count "${range_lower}..HEAD")"
if [ "$trailing" -gt 0 ]; then
    assigned=$((assigned + trailing))
    report="${report}(uncut)	${range_lower}..HEAD	${trailing}
"
fi

orphans=$((total_commits - assigned))

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
case "$MODE" in
--bullets)
    # Map each [Unreleased] bullet to the version section it truly belongs to.
    start="$(grep -n '^## \[Unreleased\]' "$CHANGELOG" | head -1 | cut -d: -f1)"
    end="$(grep -n "^## \[${last_documented}\]" "$CHANGELOG" | head -1 | cut -d: -f1)"
    if [ -z "$start" ] || [ -z "$end" ]; then
        echo "ERROR: could not locate [Unreleased] .. [$last_documented] span" >&2
        exit 2
    fi
    end=$((end - 1))
    echo "# [Unreleased] bullet -> true version section (via git blame)"
    echo "# blame attributes a line to the last commit that touched it; bullets"
    echo "# added once and never edited map exactly."
    echo
    git blame -L "${start},${end}" --line-porcelain "$CHANGELOG" 2>/dev/null \
        | awk '/^[0-9a-f]{40} /{sha=substr($1,1,7)}
               /^\t/{l=substr($0,2); if (l ~ /^- \*\*/) print sha"\t"substr(l,1,90)}' \
        | while IFS=$'\t' read -r sha text; do
            v="(uncut)"
            lower="$base_sha"
            for pv in $pending_versions; do
                up="$(cut_of "$pv")"
                if git merge-base --is-ancestor "$sha" "$up" 2>/dev/null \
                   && ! git merge-base --is-ancestor "$sha" "$lower" 2>/dev/null; then
                    v="$pv"; break
                fi
                lower="$up"
            done
            # Bullets older than the documented base belong to an already-cut release.
            if [ "$v" = "(uncut)" ] \
               && git merge-base --is-ancestor "$sha" "$base_sha" 2>/dev/null; then
                v="<=${last_documented}"
            fi
            printf '%-12s %-9s %s\n' "$v" "$sha" "$text"
        done
    ;;
--check | --report)
    echo "Release ledger reconciliation"
    echo "============================="
    echo "Last CHANGELOG-documented release : $last_documented ($base_sha)"
    echo "Version declared at HEAD          : ${head_version:-<none>}"
    if [ -f VERSION ]; then
        echo "VERSION file at HEAD              : $(tr -d '[:space:]' < VERSION)"
    fi
    echo "Commits ${base_sha}..HEAD           : $total_commits"
    echo
    echo "Derived version sections (boundaries from CLAUDE.md header history):"
    printf '%s' "$report" | while IFS=$'\t' read -r v range n; do
        [ -z "$v" ] && continue
        printf '  %-10s %-22s %4s commits\n' "$v" "$range" "$n"
    done
    echo
    if [ "$MODE" = "--report" ]; then
        echo "Merged PRs per version section:"
        lower="$base_sha"
        for v in $pending_versions; do
            up="$(cut_of "$v")"
            echo "  [$v]"
            git log --reverse --format='    %h %s' "${lower}..${up}" \
                | sed 's/$//' || true
            lower="$up"
        done
        if [ "$trailing" -gt 0 ]; then
            echo "  [(uncut) — next release]"
            git log --reverse --format='    %h %s' "${lower}..HEAD" || true
        fi
        echo
    fi
    echo "Ledger-drift assertion (every bumped version has a CHANGELOG section):"
    if [ -n "$undocumented" ]; then
        echo "  UNDOCUMENTED versions : $undocumented"
    else
        echo "  UNDOCUMENTED versions : none"
    fi
    echo
    echo "Zero-orphan assertion:"
    echo "  commits in range      : $total_commits"
    echo "  commits assigned      : $assigned"
    echo "  unclassified (orphan) : $orphans"

    rc=0
    if [ "$orphans" -ne 0 ]; then
        echo
        echo "FAIL: $orphans commit(s) could not be assigned to a version section." >&2
        rc=1
    fi
    if [ -n "$undocumented" ]; then
        echo
        echo "FAIL: version(s) bumped in the header but never cut as a CHANGELOG" >&2
        echo "      section: $undocumented" >&2
        echo "      VERSION and CHANGELOG have drifted — cut the missing section(s)." >&2
        rc=1
    fi
    if [ "$rc" -ne 0 ]; then
        exit "$rc"
    fi
    echo
    echo "PASS: every commit in ${base_sha}..HEAD maps to exactly one version section,"
    echo "      and every version bumped in the header has a CHANGELOG section."
    ;;
*)
    echo "usage: $0 [--check|--report|--bullets]" >&2
    exit 2
    ;;
esac
