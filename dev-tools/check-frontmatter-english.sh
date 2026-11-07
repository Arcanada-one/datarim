#!/usr/bin/env bash
#
# check-frontmatter-english.sh — enforce English-only `description:` field
# in framework artefacts (commands/*.md, skills/*/SKILL.md, agents/*.md).
#
# Rationale: Datarim ships as OSS framework; non-English text in
# instruction-tier fields blocks international adoption and is forbidden
# per Datarim contract (stack- and locale-agnostic for shipped code).
# This gate covers ONLY the `description:` frontmatter field — body
# translation is tracked separately as a content task.
#
# Usage: check-frontmatter-english.sh [<repo-root>]
# Exit codes: 0 PASS, 1 FAIL.

set -euo pipefail
IFS=$'\n\t'

SUMMARY_JSON=0
if [ "${1:-}" = "--summary-json" ]; then SUMMARY_JSON=1; shift; fi
if [ "${1:-}" = "--" ]; then shift; fi
ROOT="${1:-$(pwd)}"
fail=0
checked=0
cyrillic_description_count=0

valid_path_argument() {
    local LC_ALL=C
    local without_tabs="${1//$'\t'/}"
    [[ "$without_tabs" =~ ^[^[:cntrl:]]*$ ]]
}
if ! valid_path_argument "$ROOT"; then
    echo "ERROR: root contains a control character" >&2
    exit 2
fi

scan() {
    local f
    for f in "$@"; do
        [ -f "$f" ] || continue
        checked=$((checked + 1))
        local desc
        desc=$(awk '/^description:/{print; exit}' "$f" 2>/dev/null || true)
        [ -n "$desc" ] || continue
        # Cyrillic block U+0400–U+04FF in UTF-8 = bytes 0xD0 0x80 .. 0xD3 0xBF.
        # Use raw byte regex under LC_ALL=C — `grep '[А-Яа-я]'` mis-matches
        # em-dash and other multibyte punctuation under C locale.
        if echo "$desc" | LC_ALL=C grep -qE $'\xD0[\x80-\xBF]|\xD1[\x80-\xBF]|\xD2[\x80-\xBF]|\xD3[\x80-\xBF]'; then
            if [ "$SUMMARY_JSON" -eq 0 ]; then
                echo "FAIL: $f contains Cyrillic in description: field" >&2
                echo "  $desc" >&2
            fi
            fail=$((fail + 1))
            cyrillic_description_count=$((cyrillic_description_count + 1))
        fi
    done
}

scan "$ROOT"/commands/*.md
scan "$ROOT"/skills/*/SKILL.md
scan "$ROOT"/agents/*.md

if [ "$SUMMARY_JSON" -eq 1 ]; then
    if [ "$fail" -gt 0 ]; then
        printf '{"schema":"DatarimDescriptionLanguageCheckSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["CYRILLIC_DESCRIPTION_FOUND"],"checked_count":%s,"checked_count_status":"MEASURED","cyrillic_description_count":%s,"cyrillic_description_count_status":"MEASURED"}\n' "$checked" "$cyrillic_description_count"
        exit 1
    fi
    printf '{"schema":"DatarimDescriptionLanguageCheckSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"checked_count":%s,"checked_count_status":"MEASURED","cyrillic_description_count":0,"cyrillic_description_count_status":"MEASURED"}\n' "$checked"
    exit 0
fi

echo "=== Summary ==="
echo "checked=$checked artefact(s) under $ROOT"
if [ "$fail" -gt 0 ]; then
    echo "RESULT: FAIL ($fail file(s) with non-English description:)"
    exit 1
fi
echo "RESULT: PASS"
exit 0
