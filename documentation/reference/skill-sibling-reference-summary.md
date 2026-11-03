# Skill sibling-reference summary

`dev-tools/check-skill-sibling-refs.sh --summary-json [root]` emits one fixed summary of the existing skill sibling-reference scan. An omitted or empty root uses the current directory; `--` separates an optional root that begins with a dash.

The eight fields are `schema` (`DatarimSkillSiblingReferenceSummary/v1`), `result`, `exit_code`, `diagnostic_codes`, `checked_count`, `checked_count_status`, `violating_skill_count`, and `violating_skill_count_status`.

`PASS` is exit 0; `FAIL` is exit 1 with `SKILL_SIBLING_REFERENCE_INVALID`. The violation count is per skill file, not per matching line. A missing skills directory is `INPUT_UNAVAILABLE`, exit 2, with both counts `null` and `NOT_MEASURED`; an existing empty directory is a measured zero-count pass.

The existing `.system` and `references` skips, self-sibling pattern, and cross-skill exclusion are unchanged. The summary contains no skill names, paths, matched lines, or human diagnostics. It is not full Markdown link parsing, link-existence validation, or a quality/security result. Unhandled tool and parser failures remain outside the JSON contract.
