#!/usr/bin/env bash
#
# check-skill-sibling-refs.sh — verify SKILL.md files do not contain
# repo-root-relative references to their own-skill siblings.
#
# Rationale: SKILL.md and co-located bundle files (per agentskills.io v1.0.0)
# form a portable unit. Self-references in the form `skills/<own-name>/file.md`
# break when an agent reads SKILL.md from a cwd outside the framework repo
# (e.g. consumer-project cwd). Sibling references MUST be bare filenames
# resolved relative to SKILL.md's directory.
#
# Cross-skill references (one SKILL.md pointing at another skill's file)
# are out of scope — they remain repo-root-relative or fully-qualified.
#
# Usage: check-skill-sibling-refs.sh [<repo-root>]
# Exit codes: 0 PASS, 1 FAIL.

set -euo pipefail
IFS=$'\n\t'

SUMMARY_JSON=0
if [ "${1:-}" = "--summary-json" ]; then SUMMARY_JSON=1; shift; fi
if [ "${1:-}" = "--" ]; then shift; fi
ROOT="${1:-$(pwd)}"
SKILLS_DIR="$ROOT/skills"
checked=0
violating_skill_count=0

valid_path_argument() {
    local LC_ALL=C
    local without_tabs="${1//$'\t'/}"
    [[ "$without_tabs" =~ ^[^[:cntrl:]]*$ ]]
}
if ! valid_path_argument "$ROOT"; then
    echo "ERROR: root contains a control character" >&2
    exit 2
fi

if [ ! -d "$SKILLS_DIR" ]; then
    if [ "$SUMMARY_JSON" -eq 1 ]; then
        printf '{"schema":"DatarimSkillSiblingReferenceSummary/v1","result":"INPUT_UNAVAILABLE","exit_code":2,"diagnostic_codes":["SKILLS_DIRECTORY_UNAVAILABLE"],"checked_count":null,"checked_count_status":"NOT_MEASURED","violating_skill_count":null,"violating_skill_count_status":"NOT_MEASURED"}\n'
        exit 2
    fi
    echo "ERROR: $SKILLS_DIR does not exist" >&2
    exit 2
fi

fail=0

for skill_dir in "$SKILLS_DIR"/*/; do
    skill_name="$(basename "$skill_dir")"
    case "$skill_name" in
        .system|references) continue ;;
    esac
    skill_md="$skill_dir/SKILL.md"
    [ -f "$skill_md" ] || continue
    checked=$((checked + 1))

    # Look for `skills/<own-name>/<file>` in any form (backticks, parens, bare).
    if grep -qE "skills/${skill_name}/[a-z0-9_-]+\.md" "$skill_md"; then
        if [ "$SUMMARY_JSON" -eq 0 ]; then
            violations=$(grep -nE "skills/${skill_name}/[a-z0-9_-]+\.md" "$skill_md")
            echo "FAIL ($skill_name): self-skill sibling refs use repo-root-relative form (should be sibling-relative):" >&2
            echo "$violations" >&2
        fi
        fail=$((fail + 1))
        violating_skill_count=$((violating_skill_count + 1))
    fi
done

if [ "$SUMMARY_JSON" -eq 1 ]; then
    if [ "$fail" -gt 0 ]; then
        printf '{"schema":"DatarimSkillSiblingReferenceSummary/v1","result":"FAIL","exit_code":1,"diagnostic_codes":["SKILL_SIBLING_REFERENCE_INVALID"],"checked_count":%s,"checked_count_status":"MEASURED","violating_skill_count":%s,"violating_skill_count_status":"MEASURED"}\n' "$checked" "$violating_skill_count"
        exit 1
    fi
    printf '{"schema":"DatarimSkillSiblingReferenceSummary/v1","result":"PASS","exit_code":0,"diagnostic_codes":[],"checked_count":%s,"checked_count_status":"MEASURED","violating_skill_count":0,"violating_skill_count_status":"MEASURED"}\n' "$checked"
    exit 0
fi

echo "=== Summary ==="
echo "checked=$checked SKILL.md files under $SKILLS_DIR"
if [ "$fail" -gt 0 ]; then
    echo "RESULT: FAIL ($fail skill(s) carry repo-root-rel sibling refs)"
    exit 1
fi
echo "RESULT: PASS"
exit 0
