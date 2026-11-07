# Topic overlap summary

`dev-tools/check-topic-overlap.py --summary-json` emits one fixed JSON object for the existing advisory calculation. The flag is opt-in. Without it, the command retains its text and legacy `--format json` output, including silent output for missing inputs and no matches.

## Fields

The format is `DatarimTopicOverlapSummary/v1`. Every summary has exactly these fields:

| Field | Values | Meaning |
|---|---|---|
| `schema` | `DatarimTopicOverlapSummary/v1` | Format identifier. |
| `result` | `ADVISORY`, `INPUT_UNAVAILABLE`, `NO_CANDIDATES` | Outcome of the existing advisory path. |
| `exit_code` | `0` | Existing non-blocking command result. |
| `diagnostic_codes` | `[]`, `["TASK_DESCRIPTION_UNAVAILABLE"]` | Fixed code for an unavailable task description. |
| `selected_count` | Non-negative integer or `null` | Number of backlog rows selected by the existing status filter. A missing backlog is treated as an empty selection. |
| `selected_count_status` | `MEASURED`, `NOT_MEASURED` | Whether candidate selection ran. |
| `match_count` | Non-negative integer or `null` | Number of overlap matches returned by the existing calculation. |
| `match_count_status` | `MEASURED`, `NOT_MEASURED` | Whether the match count was measured. |

An ordinary completed calculation has `result: ADVISORY`, an empty diagnostic list, and measured counts, including zero matches. An empty selection has `result: NO_CANDIDATES` and both counts measured as zero. If the task description is unavailable, the result is `INPUT_UNAVAILABLE`, the diagnostic list contains `TASK_DESCRIPTION_UNAVAILABLE`, and both counts are null with `NOT_MEASURED` status. An empty task description still completes normally; it can produce zero matches against selected rows.

The summary contains no task IDs, titles, stems, source text, paths, arguments, or human diagnostics. It is a count-only view of the existing non-blocking advisory, not a duplicate-detection decision or a claim about backlog completeness.

## Scope of the JSON output

The JSON summary covers the existing ordinary advisory path. Argument parsing, `--help`, unknown or incomplete arguments, file read errors, signals, and other failures outside that path keep their existing behavior and are not normalized into a summary. No additional validator, dependency, process, traversal, or input read is introduced.
