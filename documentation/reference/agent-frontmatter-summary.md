# Agent frontmatter validation summary

`dev-tools/check-agent-frontmatter.sh --summary-json` emits one fixed JSON object for a completed validation outcome. The option is opt-in; without it, the checker keeps its existing human-readable output and exit behavior.

## Output shape

The versioned schema identifier is `DatarimAgentFrontmatterValidationSummary/v1`. The object has exactly these fields:

| Field | Meaning |
| --- | --- |
| `schema` | Fixed identifier for this summary format. |
| `result` | `PASS` or `FAIL` for a handled validation outcome. |
| `exit_code` | The corresponding normal checker result: `0` for pass or `1` for fail. |
| `diagnostic_codes` | A fixed code list; it contains no agent, tier, path, or registry values. |
| `checked_count` | Number of regular `agents/*.md` files processed, or `null` when the scan was not measured. |
| `checked_count_status` | `MEASURED` or `NOT_MEASURED`, distinguishing a completed zero-file scan from an early registry refusal. |

The fixed codes are `AGENT_FRONTMATTER_INVALID`, `NO_AGENT_FILES`, and `TIER_REGISTRY_UNAVAILABLE`.

## Outcome mapping

| Existing checker outcome | `result` / exit | `diagnostic_codes` | Count |
| --- | --- | --- | --- |
| Completed scan with no invalid frontmatter | `PASS` / `0` | `[]` | Processed file count, `MEASURED` |
| Completed scan with one or more invalid files | `FAIL` / `1` | `["AGENT_FRONTMATTER_INVALID"]` | Processed file count, `MEASURED` |
| Tier registry missing or no tier keys parsed | `FAIL` / `1` | `["TIER_REGISTRY_UNAVAILABLE"]` | `null`, `NOT_MEASURED` because the agent scan did not start |
| Registry available but no regular `agents/*.md` files | `FAIL` / `1` | `["NO_AGENT_FILES"]` | `0`, `MEASURED` because the scan loop completed |

The summary reuses the checker's existing registry read, validation loop, `fail` result, and checked-file counter. It does not define a second validation policy. The JSON communicates structural checker outcomes only; it does not establish agent quality, runtime suitability, model authorization, or security.

The summary guarantee covers these handled validation outcomes. Argument parsing, help, changing to the requested root, shell/tool failures, signals, and other unhandled failures remain in their existing output and exit domains and are not normalized into this JSON shape.
