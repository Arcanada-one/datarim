# Security finding labels validation summary

The command `dev-tools/check-security-finding-labels.py --summary-json --report <path>` emits one compact JSON object describing the existing structural validation result. It uses the checker's single existing validation call. Without `--summary-json`, the checker keeps its existing text output, diagnostics, and exit behavior.

Validate the emitted object with the local [DatarimSecurityFindingLabelsValidationSummary/v1 JSON Schema](schemas/security-finding-labels-summary.v1.schema.json) and a Draft 2020-12 JSON Schema implementation. The schema has no public identifier or endpoint; consumers should use this repository copy.

## Fixed output contract

The object has exactly these fields:

| Field | Values | Meaning |
|---|---|---|
| `schema` | `DatarimSecurityFindingLabelsValidationSummary/v1` | Output format identifier. |
| `result` | `VALID`, `INVALID`, `INPUT_REFUSED` | Structural checker outcome. |
| `exit_code` | `0`, `1`, `2` | Existing checker outcome code. |
| `diagnostic_codes` | Fixed codes below | Stable category; no report-derived message is emitted. |
| `validation_error_count` | Nonnegative integer or `null` | Number of structural validation errors, when measured. |
| `validation_error_count_status` | `MEASURED`, `NOT_MEASURED` | Whether that count was returned by validation. |

A completed validation with no errors is `VALID`, exit `0`, empty codes, and a measured count of zero. A completed validation with returned errors is `INVALID`, exit `1`, code `LABELS_INCONSISTENT`, and the measured number of errors. A caught `ValidationError` is `INPUT_REFUSED`, exit `2`, code `REPORT_INPUT_REFUSED`, and an unavailable count represented by `null` with `NOT_MEASURED`.

The only diagnostic codes are:

```text
LABELS_INCONSISTENT
REPORT_INPUT_REFUSED
```

The count is the number of checker validation errors, not the number or severity of findings. The summary does not report individual error messages. It omits report content, IDs, paths, label values, references, witness or custody data, mechanisms, exception text, and command arguments.

## Boundaries

The option does not change report selection, validation rules, label policy, witness/custody guards, or input limits. It does not reopen or revalidate the report. Existing parser/help behavior and exceptions outside the checker's `ValidationError` boundary retain their existing behavior and are not covered by the JSON contract.

This is a structural summary of a supplied report. It does not authenticate the report, establish that any finding is true, show that a reproduction occurred, qualify runtime evidence, or certify security. A syntactically accepted runtime-shaped example is only a statement about the input's structure.
