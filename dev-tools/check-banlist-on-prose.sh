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
#   check-banlist-on-prose.sh --file <path.md> [--banlist <path>] [--whitelist <path>] [--language <tag>]

set -euo pipefail
IFS=$'\n\t'

usage() {
    cat >&2 <<'USAGE'
usage: check-banlist-on-prose.sh [--summary-json] --file <path.md> [--banlist <path>] [--whitelist <path>] [--language <tag>]
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
LANGUAGE="ru"  # Preserve legacy callers; new callers pass resolved artifact language.
SUMMARY_JSON=0

while [ $# -gt 0 ]; do
    case "$1" in
        --summary-json)
            SUMMARY_JSON=1
            shift
            ;;
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
        --language)
            [ $# -ge 2 ] || usage
            LANGUAGE="$2"
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

if (( ${#LANGUAGE} > 63 )) || ! [[ "$LANGUAGE" =~ ^([A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*|[ixIX](-[A-Za-z0-9]{1,8})+)$ ]]; then
    echo "ERROR: invalid language tag" >&2
    exit 2
fi
# This vocabulary is a Russian prose rule, not an English or universal rule.
case "$LANGUAGE" in
    [rR][uU]|[rR][uU]-*) ;;
    *)
        if [ "$SUMMARY_JSON" -eq 1 ]; then
            printf '{"schema":"DatarimProseBanlistSummary/v1","result":"NOT_APPLICABLE","exit_code":0,"diagnostic_codes":["LANGUAGE_NOT_APPLICABLE"],"offence_count":null,"offence_count_status":"NOT_MEASURED"}\n'
        fi
        exit 0
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_BANLIST="$SCRIPT_DIR/../skills/human-summary/banlist.txt"
DEFAULT_WHITELIST="$SCRIPT_DIR/../skills/human-summary/whitelist.txt"

: "${BANLIST:=$DEFAULT_BANLIST}"
: "${WHITELIST:=$DEFAULT_WHITELIST}"

valid_path_argument() {
    local LC_ALL=C
    local without_tabs="${1//$'\t'/}"
    [[ "$without_tabs" =~ ^[^[:cntrl:]]*$ ]]
}
if ! valid_path_argument "$BANLIST" || ! valid_path_argument "$WHITELIST"; then
    echo "ERROR: list path contains a control character" >&2
    exit 2
fi

if [ ! -f "$BANLIST" ]; then
    if [ "$SUMMARY_JSON" -eq 1 ]; then
        printf '{"schema":"DatarimProseBanlistSummary/v1","result":"INPUT_UNAVAILABLE","exit_code":1,"diagnostic_codes":["PROSE_BANLIST_UNAVAILABLE"],"offence_count":null,"offence_count_status":"NOT_MEASURED"}\n'
        exit 1
    fi
    echo "ERROR: banlist not found: $BANLIST" >&2
    exit 1
fi
if [ ! -f "$WHITELIST" ]; then
    if [ "$SUMMARY_JSON" -eq 1 ]; then
        printf '{"schema":"DatarimProseBanlistSummary/v1","result":"INPUT_UNAVAILABLE","exit_code":1,"diagnostic_codes":["PROSE_WHITELIST_UNAVAILABLE"],"offence_count":null,"offence_count_status":"NOT_MEASURED"}\n'
        exit 1
    fi
    echo "ERROR: whitelist not found: $WHITELIST" >&2
    exit 1
fi

# awk one-shot: BEGIN loads banlist+whitelist hashmaps; main runs fence-state machine,
# tokenizes ASCII tokens length>=3, lowercases, looks up whitelist then banlist.
awk -v BANLIST="$BANLIST" -v WHITELIST="$WHITELIST" -v SUMMARY_JSON="$SUMMARY_JSON" '
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
            if (SUMMARY_JSON != "1") printf("%s:%d:%s\n", FILENAME, NR, tok)
            count++
        }
    }
}
END {
    if (SUMMARY_JSON == "1") {
        if (count > 0) {
            printf("{\"schema\":\"DatarimProseBanlistSummary/v1\",\"result\":\"OFFENCES\",\"exit_code\":1,\"diagnostic_codes\":[\"PROSE_BANLIST_MATCH\"],\"offence_count\":%d,\"offence_count_status\":\"MEASURED\"}\n", count)
            exit 1
        }
        printf("{\"schema\":\"DatarimProseBanlistSummary/v1\",\"result\":\"CLEAN\",\"exit_code\":0,\"diagnostic_codes\":[],\"offence_count\":0,\"offence_count_status\":\"MEASURED\"}\n")
        exit 0
    }
    exit (count > 0 ? 1 : 0)
}
' "$FILE"
