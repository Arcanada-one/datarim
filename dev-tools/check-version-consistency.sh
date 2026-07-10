#!/usr/bin/env bash
# check-version-consistency.sh — static version-parity gate (TUNE-0154).
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
# SCANNED SURFACES (canonical = VERSION)
#   In-repo (relative to repo root = this script's ../):
#     CLAUDE.md                              > **Version:** X.Y.Z
#     README.md                              [![Version: X.Y.Z]...badge/Version-X.Y.Z-...
#   Cross-root (relative to repo root; skipped when absent, e.g. single-repo CI):
#     ../CLAUDE.md                           Текущая версия: **X.Y.Z**
#     ../README.md                           - **Версия:** X.Y.Z
#     ../../Websites/datarim.club/config.php 'version' => 'X.Y.Z',
#
# USAGE
#   check-version-consistency.sh [--root DIR] [-h|--help]
#     --root DIR   Framework repo root holding VERSION. Default: script's ../
#                  (dev-tools/.. == repo root). Cross-root surfaces resolve
#                  relative to this root.
#
# EXIT CODES
#   0  all surfaces cite the canonical version (absent cross-root files ok)
#   1  at least one present surface disagrees with VERSION
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
every version-bearing surface cites the same value. Cross-root surfaces that
do not exist (single-repo CI checkout) are skipped, not failed.

Exit: 0 all aligned / 1 drift found / 2 usage or missing VERSION.
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
        | head -n1
}

# --- Scan -------------------------------------------------------------------
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

# --- Report -----------------------------------------------------------------
if [ -n "$mismatches" ]; then
    cat <<EOF
FAIL: version drift against VERSION ($canonical):
$mismatches
Update the listed file(s) to $canonical (single source of truth: $version_file).
EOF
    exit 1
fi

echo "OK: all $checked version surface(s) cite $canonical."
exit 0
