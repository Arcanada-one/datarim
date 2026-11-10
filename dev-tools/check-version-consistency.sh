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
#   guarded only by a manual grep (see Projects/Datarim/AGENTS.md § Version
#   consistency check).
#
#   TUNE-0174 extends the same gate with a second, isomorphic drift class:
#   framework COMPONENT COUNTS (agents / skills / commands / templates).
#   Ground truth is derived mechanically from disk (find under the repo's
#   {agents,commands,skills,templates} directories); every doc/site surface
#   that restates a count (README directory-tree comments, AGENTS.md "Agent
#   files:" / "Skill files:" / "Command files:" lines, the datarim.club
#   hero copy in three locales) is checked against that ground truth. This
#   absorbs TUNE-0154's original scope-target TUNE-0163 deferred and
#   TUNE-0174 carries forward — one enforcer, two drift classes, zero new
#   infrastructure (consumer review consolidation).
#
# SCANNED SURFACES — version (canonical = VERSION)
#   In-repo (relative to repo root = this script's ../):
#     AGENTS.md                              > **Version:** X.Y.Z
#     README.md                              [![Version: X.Y.Z]...badge/Version-X.Y.Z-...
#   Cross-root (relative to repo root; skipped when absent, e.g. single-repo CI):
#     ../../AGENTS.md                        Текущая версия: **X.Y.Z**
#     ../../README.md                        - **Версия:** X.Y.Z
#     ../../../Websites/datarim.club/config.php 'version' => 'X.Y.Z',
#
# SCANNED SURFACES — component counts (canonical = find on disk)
#   Ground truth (relative to repo root):
#     agents/*.md          -> category "agents"
#     commands/*.md        -> category "commands"
#     skills/**/SKILL.md   -> category "skills" (including nested tiers)
#     templates/**/*.md    -> category "templates" (including nested docs)
#   Claim surfaces (relative to repo root; skipped when absent):
#     AGENTS.md                                    "Agent files: ... (N agents)"
#     AGENTS.md                                    "Skill files: ... (N skills, ..."
#     AGENTS.md                                    "Command files: ... (N commands, ..."
#     README.md                                    "agents/            # Agent personas (N agents)"
#     README.md                                    "skills/             # Knowledge modules (N skills)"
#     README.md                                    "commands/           # Slash commands (N commands)"
#     README.md                                    "templates/          # Task and document templates (N templates)"
#     ../../../Websites/datarim.club/pages/about.php  "N specialized agents, N commands, N skills,"
#     (that page now derives the numbers at render time — see the derivation
#      surface class below; the literal-count rows for it were removed)
#     ../../../Websites/datarim.club/content/en.php   "N agents, N commands, N skills,"
#     ../../../Websites/datarim.club/content/ru.php   "N агентов, N команд, N навыков,"
#     (the triplet rows read the number next to each category word, so any
#      inflection of the noun — "команда", "команды", "команд", "командов" —
#      is still compared against disk instead of being reported as drift)
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
        'AGENTS.md|^> \*\*Version:\*\* ' \
        'README.md|badge/Version-' \
        '../../AGENTS.md|(Текущая версия|Текущий стабильный релиз): \*\*' \
        '../../README.md|(Текущая версия|Текущий стабильный релиз): \*\*' \
        "../../../Websites/datarim.club/config.php|'version'[[:space:]]*=>[[:space:]]*'"
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
skipped=0

while IFS='|' read -r rel regex; do
    [ -n "$rel" ] || continue
    file="$root/$rel"
    if [ ! -f "$file" ]; then
        # Cross-root surface absent (e.g. single-repo CI). Skip, do not fail,
        # but say so: when the layout moved, every one of these went silent.
        skipped=$((skipped + 1))
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
count_skills=$(find "$root/skills" -mindepth 2 -maxdepth 3 -type f -iname 'SKILL.md' ! -path "$root/skills/.*" 2>/dev/null | wc -l | tr -d '[:space:]')
count_templates=$(find "$root/templates" -mindepth 1 -maxdepth 3 -type f -name '*.md' 2>/dev/null | wc -l | tr -d '[:space:]')

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
        'AGENTS.md|agents|Agent files: .*/agents/\{name\}\.md. \(' \
        'AGENTS.md|skills|Skill files: .*/skills/\{name\}/SKILL\.md. \(' \
        'AGENTS.md|commands|Command files: .*/commands/\{name\}\.md. \(' \
        'README.md|agents|# Agent personas \(' \
        'README.md|skills|# Knowledge modules \(' \
        'README.md|commands|# Slash commands \(' \
        'README.md|templates|# Task and document templates \('
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

# --- Derivation surface table ----------------------------------------------
# A public page may state no literal count at all and render the live
# catalogue instead. Such a page cannot drift, so the gate asserts the
# derivation itself: the file must call the catalogue loader for that
# category. Each entry:
# <path-relative-to-root>@<regex-for-the-catalogue-loader-call>
# The rows are separated by "@" because the regexes contain "|".
dynamic_surfaces() {
    printf '%s\n' \
        "../../../Websites/datarim.club/pages/about.php@count\(load_all_docs\('agents'\)\)" \
        "../../../Websites/datarim.club/pages/about.php@count\(load_all_docs\('commands'\)\)" \
        "../../../Websites/datarim.club/pages/about.php@count\(load_all_docs\('skills'\)\)" \
        "../../../Websites/datarim.club/pages/home.php@count\(load_all_docs\('agents'\)\)" \
        "../../../Websites/datarim.club/pages/home.php@count\(load_all_docs\('commands'\)\)" \
        "../../../Websites/datarim.club/pages/home.php@count\(load_all_docs\('skills'\)\)"
}

# --- Literal-count surface table --------------------------------------------
# A page that derives its counts cannot drift; a page that states a literal
# count can. The pages above derive theirs, so this table asserts that they
# hold no literal "<number> <category>" claim of their own — a hardcoded
# number next to a category word is the one way such a page could still
# print a catalogue size that no longer matches disk. Each entry:
# <path-relative-to-root>@<regex-for-a-literal-catalogue-claim>
literal_surfaces() {
    printf '%s\n' \
        "../../../Websites/datarim.club/pages/about.php@([0-9]+) (agents?|commands?|skills?|агент(а|ы|ов)?|команд(а|ы|ов)?|навык(а|и|ов)?)" \
        "../../../Websites/datarim.club/pages/home.php@([0-9]+) (agents?|commands?|skills?|агент(а|ы|ов)?|команд(а|ы|ов)?|навык(а|и|ов)?)"
}

# --- Triplet surface table --------------------------------------------------
# A page may state the three catalogue sizes in one sentence. The wording of
# that sentence — and the grammatical form of its nouns — is free to change,
# so the gate reads the number that precedes each category word instead of
# one fixed phrasing. Every inflection of the word is covered ("команда",
# "команды", "команд", "командов", "навык", "навыка", "навыков"), so a size
# change can no longer turn a real drift into a false "pattern drift".
# Letter classes are deliberately avoided for the Russian words: under
# LC_ALL=C a bracket range over non-ASCII bytes is not contiguous, so the
# inflections are spelled out instead. Each entry:
# <path-relative-to-root>@<agents-regex>@<commands-regex>@<skills-regex>
triplet_surfaces() {
    printf '%s\n' \
        "../../../Websites/datarim.club/content/en.php@([0-9]+) agents?@([0-9]+) commands?@([0-9]+) skills?" \
        "../../../Websites/datarim.club/content/ru.php@([0-9]+) агент(а|ы|ов)?@([0-9]+) команд(а|ы|ов)?@([0-9]+) навык(а|и|ов)?"
}

# Extract the three counts of a catalogue-triplet sentence. Prints
# "agents commands skills", or nothing when no single line carries all three
# categories. The numbers are read next to their category words, so neither a
# reworded sentence nor an inflected noun breaks the gate.
extract_triplet() {
    local file="$1" re_a="$2" re_c="$3" re_s="$4" line re n found=""
    while IFS= read -r line; do
        printf '%s\n' "$line" | LC_ALL=C grep -qE "$re_a" || continue
        printf '%s\n' "$line" | LC_ALL=C grep -qE "$re_c" || continue
        printf '%s\n' "$line" | LC_ALL=C grep -qE "$re_s" || continue
        for re in "$re_a" "$re_c" "$re_s"; do
            n=$(printf '%s\n' "$line" | LC_ALL=C grep -oE "$re" | head -n1 | LC_ALL=C grep -oE '[0-9]+' | head -n1)
            found="$found $n"
        done
        printf '%s\n' "$found"
        return 0
    done < <(LC_ALL=C grep -E "$re_a|$re_c|$re_s" "$file" 2>/dev/null)
    return 0
}

# --- Scan (component counts) -------------------------------------------------
count_mismatches=""
count_checked=0

while IFS='|' read -r rel category anchor; do
    [ -n "$rel" ] || continue
    file="$root/$rel"
    if [ ! -f "$file" ]; then
        # Cross-root surface absent (e.g. single-repo CI). Skip, do not fail.
        skipped=$((skipped + 1))
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

# --- Scan (derivation surfaces) ----------------------------------------------
while IFS='@' read -r rel needle; do
    [ -n "$rel" ] || continue
    file="$root/$rel"
    if [ ! -f "$file" ]; then
        skipped=$((skipped + 1))
        continue
    fi
    if LC_ALL=C grep -qE -- "$needle" "$file" 2>/dev/null; then
        count_checked=$((count_checked + 1))
    else
        count_mismatches+="  $rel — does not derive the catalogue count ($needle)"$'\n'
    fi
done < <(dynamic_surfaces)

# --- Scan (literal-count surfaces) -------------------------------------------
while IFS='@' read -r rel pattern; do
    [ -n "$rel" ] || continue
    file="$root/$rel"
    if [ ! -f "$file" ]; then
        skipped=$((skipped + 1))
        continue
    fi
    if LC_ALL=C grep -qE -- "$pattern" "$file" 2>/dev/null; then
        count_mismatches+="  $rel — states a literal catalogue count next to a category word ($pattern)"$'\n'
    else
        count_checked=$((count_checked + 1))
    fi
done < <(literal_surfaces)

# --- Scan (triplet surfaces) -------------------------------------------------
while IFS='@' read -r rel re_a re_c re_s; do
    [ -n "$rel" ] || continue
    file="$root/$rel"
    if [ ! -f "$file" ]; then
        skipped=$((skipped + 1))
        continue
    fi
    found=$(extract_triplet "$file" "$re_a" "$re_c" "$re_s")
    if [ -z "$found" ]; then
        count_mismatches+="  $rel — no catalogue triplet matched (pattern drift?)"$'\n'
        continue
    fi
    count_checked=$((count_checked + 1))
    read -r found_agents found_commands found_skills <<<"$found"
    for pair in "agents:$found_agents:$count_agents" "commands:$found_commands:$count_commands" "skills:$found_skills:$count_skills"; do
        category=${pair%%:*}
        rest=${pair#*:}
        claimed=${rest%%:*}
        expected=${rest##*:}
        if [ "$claimed" != "$expected" ]; then
            count_mismatches+="  $rel [$category] — claims $claimed, disk has $expected"$'\n'
        fi
    done
done < <(triplet_surfaces)

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

echo "OK: all $checked version surface(s) cite $canonical; all $count_checked component-count claim(s) match disk (agents=$count_agents, commands=$count_commands, skills=$count_skills, templates=$count_templates); $skipped cross-root surface(s) absent, not checked."
exit 0
