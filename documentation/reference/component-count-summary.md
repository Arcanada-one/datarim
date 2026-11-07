# Component-count summary

`dev-tools/check-component-counts.sh --summary-json` reports the existing component-count drift check as one fixed JSON object. It reuses the same counts and claim comparisons as the text modes. When both `--summary-json` and `--report` are supplied, JSON output takes precedence.

The object has exactly six fields: `schema` (`DatarimComponentCountSummary/v1`), `result`, `exit_code`, `diagnostic_codes`, `drift_count`, and `drift_count_status`.

| Result | Exit | Diagnostic | Count |
|---|---:|---|---|
| `PASS` | 0 | `[]` | measured zero |
| `FAIL` | 1 | `COMPONENT_COUNT_DRIFT` | measured positive number of mismatched claims |
| `INPUT_UNAVAILABLE` | 3 | `COMPONENT_ROOT_UNAVAILABLE` | `null`, `NOT_MEASURED` |

The summary omits filenames, category names, claimed and actual values, paths, and human diagnostics. It does not add a scan or change the count patterns, depth, hidden-skill exclusion, or check/report behavior without the option. An unavailable root is distinct from a completed check with no drift. Parser errors and other unhandled failures remain outside the JSON contract. This is a repository self-check, not a cross-repository or website comparison.
