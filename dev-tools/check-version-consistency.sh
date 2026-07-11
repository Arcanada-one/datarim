#!/usr/bin/env bash
# check-version-consistency.sh — static version-parity gate (TUNE-0154)
#                                 + framework component counts-drift gate (TUNE-0174).
#
# PURPOSE
#   Mechanical CI enforcer for TUNE-0019. Reads the canonical framework
#   version from the `VERSION` file and asserts that every surface that
#   restates the version cites the SAME value. Any disagreement fails the
#   gate (exit 1) with a per-file diff, so version drift is caught pre-commit
#   / pre-merge instead of manually during a release cycle.
#
#   Unlike scripts/version-consistency-check.sh (TUNE-0080), which is a
#   git-diff-driven pre-archive gate scoped to the framework repo only, this
#   script is a static, diff-independent scanner. It additionally covers the
#   project-level wrappers and the datarim.club site config that live OUTSIDE
#   the framework git repo (in the parent workspace) and were previously
#   guarded only by a manual grep (see Projects/Datarim/CLAUDE.md § Version
#   consistency check).
#
#   TUNE-0174 extends the same gate with a second, isomorphic drift class:
#   framework COMPONENT COUNTS (agents / skills / commands / templates).
#   Ground truth is derived mechanically from disk (find under the repo's
#   {agents,commands,skills,templates} directories); every doc/site surface
#   that restates a count (README directory-tree comments, CLAUDE.md "Agent
#   files:" / "Skill files:" / "Command files:" lines, the datarim.club
#   hero copy in three locales) is checked against that ground truth. This
#   absorbs TUNE-0154's original scope-target TUNE-0163 deferred and
#   TUNE-0174 carries forward — one enforcer, two drift classes, zero new
#   infrastructure (ARCA-0142 consolidation).
#
# SCANNED SURFACES — version (canonical = VERSION)
#   In-repo (relative to repo root = this script's ../):
#     CLAUDE.md                              > **Version:** X.Y.Z
#     README.md                              [![Version: X.Y.Z]...badge/Version-X.Y.Z-...
#   Cross-root (relative to repo root; skipped when absent, e.g. single-repo CI):
#     ../CLAUDE.md                           Текущая версия: **X.Y.Z**
#     ../README.md                           - **Версия:** X.Y.Z
#     ../../Websites/datarim.club/config.php 'version' => 'X.Y.Z',
#
# SCANNED SURFACES — component counts (canonical = find on disk)
#   Ground truth (relative to repo root):
#     agents/*.md          -> category "agents"
#     commands/*.md        -> category "commands"
#     skills/*/SKILL.md    -> category "skills"
#     templates/*.md       -> category "templates"
#   Claim surfaces (relative to repo root; skipped when absent):
#     CLAUDE.md                                    "Agent files: ... (N agents)"
#     CLAUDE.md                                    "Skill files: ... (N skills, ..."
#     CLAUDE.md                                    "Command files: ... (N commands, ..."
#     README.md                                    "agents/            # Agent personas (N agents)"
#     README.md                                    "skills/             # Knowledge modules (N skills)"
#     README.md                                    "commands/           # Slash commands (N commands)"
#     README.md                                    "templates/          # Task and document templates (N templates)"
#     ../../Websites/datarim.club/pages/about.php  "N specialized agents, N commands, N skills,"
#     ../../Websites/datarim.club/content/en.php   "N agents, N commands, N skills,"
#     ../../Websites/datarim.club/content/ru.php   "N агентов, N команд, N навыков,"
#
# USAGE
#   check-version-consistency.sh [--root DIR] [-h|--help]
#     --root DIR   Framework repo root holding VERSION. Default: script's ../
#                  (dev-tools/.. == repo root). Cross-root surfaces resolve
#                  relative to this root.
#
# EXIT CODES
#   0  all surfaces cite the canonical version AND all count claims match
#      ground truth (absent cross-root files ok)
#   1  at least one present surface disagrees with VERSION, or at least one
#      present count claim disagrees with the on-disk ground truth
#   2  usage error / missing VERSION / unreadable canonical version
#
# Read-only: plain text reads + grep. No mutation, no eval, no network.
# Conventions: C1 (printf lists), C2 (IFS= read -r loops), C4 (LC_ALL=C regex).
set -euo pipefail

print_usage() {
    cat >&2 <<'EOF'
Usage:
  check-version-consistency.sh [--root DIR]

Reads DIR/VERSION (default: this script's parent repo root) and verifies that
every version-bearing surface cites the same value, AND that every framework
component-count claim (agents/skills/commands/templates) matches the on-disk
ground truth. Cross-root surfaces that do not exist (single-repo CI checkout)
are skipped, not failed.

Exit: 0 all aligned / 1 drift found (version and/or counts) / 2 usage or
missing VERSION.
EOF
}

# --- Argument parsing -------------------------------------------------------
root=""
while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || { echo "ERROR: --root needs a DIR argument" >&2; exit 2; }
            root="$2"; shift 2 ;;
        -h|--help) print_usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "ERROR: unknown flag: $1" >&2; print_usage; exit 2 ;;
        *)  echo "ERROR: unexpected argument: $1" >&2; print_usage; exit 2 ;;
    esac
done

# Default root: the repo root that contains dev-tools/ (i.e. this script's ../).
if [ -z "$root" ]; then
    script_dir=$(unset CDPATH && cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    root=$(unset CDPATH && cd -- "$script_dir/.." && pwd)
fi

version_file="$root/VERSION"
if [ ! -f "$version_file" ]; then
    echo "ERROR: VERSION file not found at: $version_file" >&2
    exit 2
fi

# Canonical version. Tolerate trailing whitespace / blank lines.
canonical=$(tr -d '[:space:]' < "$version_file")
if [ -z "$canonical" ]; then
    echo "ERROR: VERSION file is empty: $version_file" >&2
    exit 2
fi

# --- Surface table ----------------------------------------------------------
# Each entry: <path-relative-to-root>|<anchor-extended-regex>
# The anchor regex matches the line context immediately BEFORE the version
# token (so the correct line is selected); the X.Y.Z token that follows is
# then isolated. cross_root files (../, ../../) are skipped when absent.
surfaces() {
    printf '%s\n' \
        'CLAUDE.md|^> \*\*Version:\*\* ' \
        'README.md|badge/Version-' \
        '../CLAUDE.md|Текущая версия: \*\*' \
        '../README.md|\*\*Версия:\*\* ' \
        "../../Websites/datarim.club/config.php|'version'[[:space:]]*=>[[:space:]]*'"
}

# Extract the version token that follows ANCHOR in FILE. Grabs the anchor line,
# then the first X.Y.Z token appearing after the anchor prefix. Emits the token
# on stdout, or nothing if no line matches. LC_ALL=C keeps [0-9] byte-stable (C4)
# and the alternate `grep -oP`-free approach avoids sed-delimiter collisions
# with '/' inside anchors (e.g. badge/Version-).
extract_version() {
    local file="$1" anchor="$2" line
    line=$(LC_ALL=C grep -m1 -E "$anchor" "$file" 2>/dev/null) || return 0
    # Strip everything up to and including the anchor, then take the leading
    # X.Y.Z of the remainder.
    printf '%s\n' "$line" \
        | LC_ALL=C sed -E "s@^.*${anchor}@@" \
        | LC_ALL=C grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' \
        | head -n1 || true
}

# --- Scan (version) ----------------------------------------------------------
mismatches=""
checked=0

while IFS='|' read -r rel regex; do
    [ -n "$rel" ] || continue
    file="$root/$rel"
    if [ ! -f "$file" ]; then
        # Cross-root surface absent (e.g. single-repo CI). Skip, do not fail.
        continue
    fi
    found=$(extract_version "$file" "$regex")
    if [ -z "$found" ]; then
        mismatches+="  $rel — no version string matched (pattern drift?)"$'\n'
        continue
    fi
    checked=$((checked + 1))
    if [ "$found" != "$canonical" ]; then
        mismatches+="  $rel — found $found, expected $canonical"$'\n'
    fi
done < <(surfaces)

# --- Ground truth (component counts) ----------------------------------------
# One find per category, restricted to the in-repo directories. Categories
# that do not exist at $root (e.g. a stripped-down checkout) count as 0 and
# are still checked against any present claim — a claim citing a non-zero
# count against a missing directory is real drift, not a skip condition.
count_agents=$(find "$root/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d '[:space:]')
count_commands=$(find "$root/commands" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d '[:space:]')
count_skills=$(find "$root/skills" -mindepth 2 -maxdepth 2 -iname 'SKILL.md' 2>/dev/null | wc -l | tr -d '[:space:]')
count_templates=$(find "$root/templates" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d '[:space:]')

ground_truth_for() {
    case "$1" in
        agents) printf '%s' "$count_agents" ;;
        commands) printf '%s' "$count_commands" ;;
        skills) printf '%s' "$count_skills" ;;
        templates) printf '%s' "$count_templates" ;;
        *) printf '' ;;
    esac
}

# --- Count-claim surface table ------------------------------------------------
# Each entry: <path-relative-to-root>|<category>|<anchor-extended-regex>
# The anchor regex matches immediately BEFORE the count digits (same
# convention as the version surfaces above); the digits that follow the
# anchor are isolated and compared against ground_truth_for(category). Every
# row uses a category-specific anchor so extraction never has to disambiguate
# multiple numbers appearing on one shared line (e.g. the datarim.club hero
# copy restates all three categories in a single sentence).
count_surfaces() {
    printf '%s\n' \
        'CLAUDE.md|agents|Agent files: .*/agents/\{name\}\.md. \(' \
        'CLAUDE.md|skills|Skill files: .*/skills/\{name\}/SKILL\.md. \(' \
        'CLAUDE.md|commands|Command files: .*/commands/\{name\}\.md. \(' \
        'README.md|agents|# Agent personas \(' \
        'README.md|skills|# Knowledge modules \(' \
        'README.md|commands|# Slash commands \(' \
        'README.md|templates|# Task and document templates \(' \
        '../../Websites/datarim.club/pages/about.php|agents|The framework includes ' \
        '../../Websites/datarim.club/pages/about.php|commands|includes [0-9]+ specialized agents, ' \
        '../../Websites/datarim.club/pages/about.php|skills|includes [0-9]+ specialized agents, [0-9]+ commands, ' \
        '../../Websites/datarim.club/content/en.php|agents|Structure any project into iterative tasks\. ' \
        '../../Websites/datarim.club/content/en.php|commands|iterative tasks\. [0-9]+ agents, ' \
        '../../Websites/datarim.club/content/en.php|skills|iterative tasks\. [0-9]+ agents, [0-9]+ commands, ' \
        '../../Websites/datarim.club/content/ru.php|agents|итерационные задачи\. ' \
        '../../Websites/datarim.club/content/ru.php|commands|итерационные задачи\. [0-9]+ агентов, ' \
        '../../Websites/datarim.club/content/ru.php|skills|итерационные задачи\. [0-9]+ агентов, [0-9]+ команд, '
}

# Extract the integer count that follows ANCHOR in FILE (first line matching
# ANCHOR only). Same strip-then-isolate approach as extract_version, but
# pulls a bare integer instead of an X.Y.Z token.
extract_count() {
    local file="$1" anchor="$2" line
    line=$(LC_ALL=C grep -m1 -E "$anchor" "$file" 2>/dev/null) || return 0
    printf '%s\n' "$line" \
        | LC_ALL=C sed -E "s@^.*${anchor}@@" \
        | LC_ALL=C grep -oE '^[0-9]+' \
        | head -n1 || true
}

# --- Scan (component counts) -------------------------------------------------
count_mismatches=""
count_checked=0

while IFS='|' read -r rel category anchor; do
    [ -n "$rel" ] || continue
    file="$root/$rel"
    if [ ! -f "$file" ]; then
        # Cross-root surface absent (e.g. single-repo CI). Skip, do not fail.
        continue
    fi
    expected=$(ground_truth_for "$category")
    found=$(extract_count "$file" "$anchor")
    if [ -z "$found" ]; then
        count_mismatches+="  $rel [$category] — no count matched (pattern drift?)"$'\n'
        continue
    fi
    count_checked=$((count_checked + 1))
    if [ "$found" != "$expected" ]; then
        count_mismatches+="  $rel [$category] — claims $found, disk has $expected"$'\n'
    fi
done < <(count_surfaces)

# --- Report -------------------------------------------------------------------
fail=0

if [ -n "$mismatches" ]; then
    fail=1
    cat <<EOF
FAIL: version drift against VERSION ($canonical):
$mismatches
Update the listed file(s) to $canonical (single source of truth: $version_file).
EOF
fi

if [ -n "$count_mismatches" ]; then
    fail=1
    cat <<EOF
FAIL: framework component-count drift against disk (agents=$count_agents, commands=$count_commands, skills=$count_skills, templates=$count_templates):
$count_mismatches
Update the listed file(s) to match the on-disk counts, or re-run this gate
after the component addition/removal is complete.
EOF
fi

if [ "$fail" -ne 0 ]; then
    exit 1
fi

echo "OK: all $checked version surface(s) cite $canonical; all $count_checked component-count claim(s) match disk (agents=$count_agents, commands=$count_commands, skills=$count_skills, templates=$count_templates)."
exit 0
