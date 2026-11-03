# Plan-completion validation summary

`dev-tools/check-plan-completion.py --summary-json` emits one compact JSON line for the selected `--report`. It uses the existing report read and validation result once; it does not change the report, recorded status, or validation policy. Without `--summary-json`, the checker retains its existing text output and exit codes.

## Output

The summary uses `DatarimPlanCompletionValidationSummary/v1` with exactly these top-level fields:

| Field | Values | Meaning |
|---|---|---|
| `schema` | `DatarimPlanCompletionValidationSummary/v1` | Summary format identifier. |
| `result` | `VALID`, `INVALID`, `UNREADABLE` | Outcome of the existing report read and structural validation. |
| `exit_code` | `0`, `1`, `2` | Existing checker result: valid, invalid, or unreadable input. |
| `diagnostic_codes` | Fixed string array | Unique, allowlisted validation codes in first-occurrence order; `REPORT_UNREADABLE` for an unreadable report. |
| `validation_error_count` | Nonnegative integer or `null` | Number of existing validation errors when validation ran; `null` when the report could not be read. |
| `validation_error_count_status` | `MEASURED` or `NOT_MEASURED` | Whether the validation-error count was measured. |

Examples:

```text
{"schema":"DatarimPlanCompletionValidationSummary/v1","result":"VALID","exit_code":0,"diagnostic_codes":[],"validation_error_count":0,"validation_error_count_status":"MEASURED"}
```

```text
{"schema":"DatarimPlanCompletionValidationSummary/v1","result":"UNREADABLE","exit_code":2,"diagnostic_codes":["REPORT_UNREADABLE"],"validation_error_count":null,"validation_error_count_status":"NOT_MEASURED"}
```

## Diagnostic codes

Only the following fixed codes can appear in `diagnostic_codes`:

| Code | Existing structural condition |
|---|---|
| `E_SECTION_MISSING` | The Layer 3 Plan Completeness section is missing. |
| `E_STATUS_TABLE_MISSING` | The section has no status table. |
| `E_TABLE_HEADERS_INVALID` | The table headers do not match the expected fields. |
| `E_TABLE_SEPARATOR_MISSING` | The Markdown header separator is missing or invalid. |
| `E_TABLE_ROW_SHAPE_INVALID` | A row does not have seven fields. |
| `E_DELIVERABLE_REQUIRED` | A deliverable name is empty. |
| `E_STATUS_UNSUPPORTED` | A row uses a status outside the existing set. |
| `E_EVIDENCE_REQUIRED` | A row has no evidence value. |
| `E_DONE_REASON_FORBIDDEN` | A `DONE` row has a discrepancy reason. |
| `E_DONE_GAP_FORBIDDEN` | A `DONE` row has a missing-evidence value. |
| `E_DISCREPANCY_REASON_UNSUPPORTED` | A non-`DONE` row has an unsupported reason. |
| `E_CHANGED_FIELDS_REQUIRED` | A `CHANGED` row lacks its planned or replacement value. |
| `E_UNVERIFIABLE_GAP_REQUIRED` | An `UNVERIFIABLE` row lacks its exact missing check. |
| `E_GAP_ONLY_UNVERIFIABLE` | A status other than `UNVERIFIABLE` supplies a missing-evidence value. |
| `E_STATUS_TABLE_EMPTY` | The table contains no row with the expected seven fields. |
| `E_VALIDATION_FAILED` | A future or unexpected internal diagnostic has no known mapping. |
| `REPORT_UNREADABLE` | The report could not be read or decoded as UTF-8 text. |

Validation codes are fixed and deduplicated. The summary omits validation prose, row labels, status values, report content, paths, arguments, and exception text. An unreadable input has no validation error count because validation did not run.

## Boundaries

- This is an opt-in summary for this checker, not a general Datarim CLI stability promise.
- The existing `DONE`, `PARTIAL`, `NOT DONE`, `CHANGED`, and `UNVERIFIABLE` values describe the report's recorded plan table. A `DONE` row is not proof of task acceptance, evidence authenticity, or runtime behavior.
- Argument parsing and `--help` occur before report processing and keep argparse's existing text behavior; they are outside the JSON-output guarantee. Signals, process launch failures, and broken output pipes are also outside that guarantee.
- The JSON describes the existing structural check only. It does not read or write task state, promote a status, validate evidence truth, or establish live/runtime acceptance.

Run the summary mode with:

```sh
python3 dev-tools/check-plan-completion.py --report <report-path> --summary-json
```
