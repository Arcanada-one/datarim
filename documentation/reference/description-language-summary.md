# Description-language summary

Use `dev-tools/check-frontmatter-english.sh --summary-json [root]` for a fixed result from the existing description scan. The root is optional; an omitted or empty root uses the current directory. `--` may separate the option from a root beginning with a dash.

The eight fields are `schema` (`DatarimDescriptionLanguageCheckSummary/v1`), `result`, `exit_code`, `diagnostic_codes`, `checked_count`, `checked_count_status`, `cyrillic_description_count`, and `cyrillic_description_count_status`.

`PASS` is exit 0 with both counts measured; `FAIL` is exit 1 with `CYRILLIC_DESCRIPTION_FOUND`. A missing description is included in `checked_count` but is not a Cyrillic finding. An absent root or no matching regular files remains a completed zero-count pass, so the result does not prove that a root exists or that every artifact was checked.

The checker retains its byte-level Cyrillic predicate, first `description:` line selection, and scope of `commands/*.md`, `skills/*/SKILL.md`, and `agents/*.md`. Summary mode omits dynamic filenames, descriptions, paths, and human output. It is not a general language detector, body check, or content-quality result. Parser, tool, signal, and unhandled errors remain outside the JSON contract; no-flag output and exits remain unchanged for supported inputs.
