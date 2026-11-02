# Topic-overlap summary schema and consumer reference

Use the portable [Draft 2020-12 schema](schemas/topic-overlap-summary.v1.schema.json)
to validate a `DatarimTopicOverlapSummary/v1` JSON summary independently. The
schema checks the fixed summary structure; it does not execute the producer,
inspect task descriptions or backlog contents, or determine whether an overlap
is meaningful.

## Fields

Every summary has exactly these eight fields:

| Field | Values | Meaning |
|---|---|---|
| `schema` | `DatarimTopicOverlapSummary/v1` | Fixed format identifier. |
| `result` | `ADVISORY`, `NO_CANDIDATES`, `INPUT_UNAVAILABLE` | Outcome of the existing advisory path. |
| `exit_code` | `0` | Existing non-blocking command result represented by the summary. |
| `diagnostic_codes` | `[]` or `["TASK_DESCRIPTION_UNAVAILABLE"]` | Fixed code when the task description cannot be read. |
| `selected_count` | Non-negative integer or `null` | Number of backlog rows selected by the existing status filter, if measured. |
| `selected_count_status` | `MEASURED`, `NOT_MEASURED` | Whether candidate selection ran. |
| `match_count` | Non-negative integer or `null` | Number of matches returned by the existing overlap calculation, if measured. |
| `match_count_status` | `MEASURED`, `NOT_MEASURED` | Whether the match count was measured. |

## Supported profiles

- **`ADVISORY`** has exit code `0`, no diagnostic codes, and a measured positive
  `selected_count`. Its measured `match_count` can be zero or greater; no matches
  do not change the advisory result.
- **`NO_CANDIDATES`** has exit code `0`, no diagnostic codes, and both counts
  measured as zero. The producer uses this when its existing selection step
  yields no rows, including an empty or missing backlog.
- **`INPUT_UNAVAILABLE`** has exit code `0`, code
  `TASK_DESCRIPTION_UNAVAILABLE`, and null counts with `NOT_MEASURED` statuses.
  This distinguishes an unavailable task description from a completed empty
  selection or a measured zero-match result.

The schema requires the exact field set, JSON types, fixed values, and these
result/code/count-availability correlations. JSON Schema's `integer` type
accepts mathematically integral JSON numbers such as `1.0`; booleans are not
integers.

## Limits

This schema does not enforce arithmetic relationships between the counts, rank
or validate candidates, establish semantic similarity, prove backlog completeness,
parse source task data, or establish truth, provenance, security, or runtime
acceptance. It describes the producer's fixed summary format when emitted; it
does not establish that the producer is available on a particular branch or
runtime. The output is a count-only advisory, not a duplicate-task decision.
