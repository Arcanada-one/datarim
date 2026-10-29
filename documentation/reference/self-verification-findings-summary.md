# Self-verification findings summary

`dev-tools/validate-self-verification-findings.py --summary-json` emits a fixed JSON object without finding details. It uses the existing input parsing and record validation paths. Without `--summary-json`, the existing detailed JSON output remains in use.

## Fields

The versioned format is `DatarimSelfVerificationFindingsSummary/v1`. Every summary object has exactly these fields:

| Field | Values | Meaning |
|---|---|---|
| `schema` | `DatarimSelfVerificationFindingsSummary/v1` | Format identifier. |
| `result` | `VALID`, `INVALID`, `INPUT_REFUSED` | Existing completed record-validation result or an existing early input refusal. |
| `exit_code` | `0`, `1` | The validator's corresponding exit result for the summarized path. |
| `diagnostic_codes` | `[]`, `["FINDINGS_INVALID"]`, `["FINDINGS_JSON_INVALID"]`, `["FINDINGS_SHAPE_INVALID"]` | Fixed code for the existing record-validation, JSON-parse, or top-level input-shape branch. |
| `normalized_count` | Non-negative integer or `null` | Number of records accepted by the existing normalization loop. `null` means the loop was not reached. |
| `normalized_count_status` | `MEASURED`, `NOT_MEASURED` | Whether the existing normalization path supplied a count. |
| `malformed_count` | Non-negative integer or `null` | Number of records rejected by the existing normalization loop. `null` means the loop was not reached. |
| `malformed_count_status` | `MEASURED`, `NOT_MEASURED` | Whether the existing normalization path supplied a count. |

Completed validation returns `VALID`, exit `0`, no diagnostic codes, and measured counts when no records are malformed. If one or more records are malformed, it returns `INVALID`, exit `1`, `FINDINGS_INVALID`, and measured counts. A JSON decoding refusal returns `INPUT_REFUSED`, exit `1`, `FINDINGS_JSON_INVALID`; an unsupported top-level shape returns `INPUT_REFUSED`, exit `1`, `FINDINGS_SHAPE_INVALID`. Both early-refusal paths set both counts to `null` with `NOT_MEASURED`, because record normalization did not run. Missing input follows the existing JSON decoding path.

The summary does not contain findings, excerpts, evidence sources, paths, raw records, suggested fixes, exception text, arguments, or task identifiers. `normalized_count` reflects records accepted by the existing loop, including records that the existing policy marks discarded for absent evidence. This interface does not change that policy, validation, legacy upgrade, round handling, or the default output.

## Scope of the JSON output

The JSON contract covers the existing JSON decoding refusal, top-level shape refusal, and completed record-validation paths when `--summary-json` is selected. Argument parsing and usage failures (including invalid round limits), help, signals, and other unhandled failures retain their existing behavior and are not normalized into this summary. The interface does not promise JSON for every invocation failure.
