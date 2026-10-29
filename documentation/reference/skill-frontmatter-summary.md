# Skill frontmatter validation summary

`dev-tools/check-skill-frontmatter.sh --summary-json` emits a single JSON object for an ordinary completed scan. It reuses the checker's existing traversal, predicates, and counters. Without `--summary-json`, the existing human-readable output remains in use.

## Fields

The versioned format is `DatarimSkillFrontmatterValidationSummary/v1`. Every completed-scan object has exactly these fields:

| Field | Values | Meaning |
|---|---|---|
| `schema` | `DatarimSkillFrontmatterValidationSummary/v1` | Format identifier. |
| `result` | `PASS`, `FAIL` | Existing checker decision. |
| `exit_code` | `0`, `1` | Existing completed-scan exit result. |
| `diagnostic_codes` | `[]`, `["SKILL_FRONTMATTER_INVALID"]` | Fixed code for the existing failure predicate; warnings alone do not add a failure code. |
| `checked_count` | Non-negative integer | Number of frontmatter blocks checked by the existing scan. |
| `checked_count_status` | `MEASURED` | The completed scan measured the count, including when it is zero. |
| `warning_count` | Non-negative integer | Number of existing warning findings. |
| `warning_count_status` | `MEASURED` | The completed scan measured the warning count, including when it is zero. |

For completed scans, `PASS` corresponds to exit code `0` and an empty code list. `FAIL` corresponds to exit code `1` and `SKILL_FRONTMATTER_INVALID`. A legacy top-level `runtime:` warning remains warning-only: the result is `PASS` with exit code `0`, while `warning_count` records the warning.

The summary does not include skill names, paths, frontmatter values, or human diagnostics. Counts describe the checker's structural scan; they do not establish skill quality, safety, authority, admission, or runtime behavior.

## Scope of the JSON output

The JSON guarantee covers an ordinary completed scan, including the existing skill checks and the `AGENTS.md` / `CLAUDE.md` repository guards. Argument parsing, `--help`, unknown or incomplete arguments, root-directory changes, signals, missing tools, and other failures outside that completed-scan path retain their existing behavior and are not normalized into JSON. This interface does not promise JSON for every invocation failure.
