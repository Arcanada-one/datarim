#!/usr/bin/env bash
# check-banlist-on-prose.sh — fence-aware banlist validator for archive/compliance prose.
#
# Per creative-TUNE-0255-architecture-banlist-validator.md (Option B awk one-shot):
#   - bash wrapper does argparse + path-traversal regex + default path resolution
#   - awk one-shot does fence-state machine + tokenize + whitelist/banlist lookup
#
# Contract (PRD V-AC-4):
#   exit 0  → clean
#   exit 1  → offences found (stdout: file:line:token, one per line)
#   exit 2  → usage error
#
# API:
#   check-banlist-on-prose.sh --file <path.md> [--banlist <path>] [--whitelist <path>]

set -euo pipefail

usage() {
    cat >&2 <<'USAGE'
usage: check-banlist-on-prose.sh --file <path.md> [--banlist <path>] [--whitelist <path>]
  --file       markdown file to scan (required; must match ^[A-Za-z0-9._/-]+\.md$)
  --banlist    banlist source (default: <script-dir>/../skills/human-summary/banlist.txt)
  --whitelist  whitelist source (default: <script-dir>/../skills/human-summary/whitelist.txt)
exit codes:
  0 clean, 1 offences (stdout file:line:token), 2 usage error
USAGE
    exit 2
}

FILE=""
BANLIST=""
WHITELIST=""

while [ $# -gt 0 ]; do
    case "$1" in
        --file)
            [ $# -ge 2 ] || usage
            FILE="$2"
            shift 2
            ;;
        --banlist)
            [ $# -ge 2 ] || usage
            BANLIST="$2"
            shift 2
            ;;
        --whitelist)
            [ $# -ge 2 ] || usage
            WHITELIST="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

[ -n "$FILE" ] || usage

# Path-traversal / shape guard (Security Mandate § S1).
if ! printf '%s' "$FILE" | grep -Eq '^[A-Za-z0-9._/-]+\.md$'; then
    echo "ERROR: --file must match ^[A-Za-z0-9._/-]+\\.md\$ (got: $FILE)" >&2
    exit 2
fi

if [ ! -f "$FILE" ]; then
    echo "ERROR: file not found: $FILE" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_BANLIST="$SCRIPT_DIR/../skills/human-summary/banlist.txt"
DEFAULT_WHITELIST="$SCRIPT_DIR/../skills/human-summary/whitelist.txt"

: "${BANLIST:=$DEFAULT_BANLIST}"
: "${WHITELIST:=$DEFAULT_WHITELIST}"

if [ ! -f "$BANLIST" ]; then
    echo "ERROR: banlist not found: $BANLIST" >&2
    exit 1
fi
if [ ! -f "$WHITELIST" ]; then
    echo "ERROR: whitelist not found: $WHITELIST" >&2
    exit 1
fi

# awk one-shot: BEGIN loads banlist+whitelist hashmaps; main runs fence-state machine,
# tokenizes ASCII tokens length>=3, lowercases, looks up whitelist then banlist.
awk -v BANLIST="$BANLIST" -v WHITELIST="$WHITELIST" '
BEGIN {
    # Load banlist
    while ((getline line < BANLIST) > 0) {
        sub(/#.*/, "", line)
        gsub(/[ \t\r]+$/, "", line)
        gsub(/^[ \t]+/, "", line)
        if (line == "") continue
        banlist[tolower(line)] = 1
    }
    close(BANLIST)
    # Load whitelist
    while ((getline line < WHITELIST) > 0) {
        sub(/#.*/, "", line)
        gsub(/[ \t\r]+$/, "", line)
        gsub(/^[ \t]+/, "", line)
        if (line == "") continue
        whitelist[tolower(line)] = 1
    }
    close(WHITELIST)
    in_fence = 0
    in_yaml = 0
    count = 0
}
# YAML frontmatter: opening --- on line 1, closing --- on subsequent line.
NR == 1 && /^---[[:space:]]*$/ { in_yaml = 1; next }
in_yaml && /^---[[:space:]]*$/ { in_yaml = 0; next }
in_yaml { next }
/<!-- gate:literal -->/ { in_fence = 1; next }
/<!-- \/gate:literal -->/ { in_fence = 0; next }
/<!-- gate:example-only -->/ { in_fence = 1; next }
/<!-- \/gate:example-only -->/ { in_fence = 0; next }
{
    if (in_fence) next
    line = $0
    gsub(/[^A-Za-z]+/, " ", line)
    n = split(line, tokens, " ")
    for (i = 1; i <= n; i++) {
        tok = tolower(tokens[i])
        if (length(tok) < 3) continue
        if (tok in whitelist) continue
        if (tok in banlist) {
            printf("%s:%d:%s\n", FILENAME, NR, tok)
            count++
        }
    }
}
END {
    exit (count > 0 ? 1 : 0)
}
' "$FILE"
