# Test Value Card Validation Summary

The existing validator can emit a versioned JSON summary for scripts that need a stable result without parsing human-readable output:

```bash
python3 dev-tools/check-test-value-card.py --card path/to/card.md --summary-json
```

The option is opt-in. Without it, the validator keeps its current human output and exit behavior. Both modes read the selected card once and call the same `validate_text` rules once. The JSON object is written as one compact line to stdout; it contains no card path, card values, raw validator details, exception text, arguments or environment data.

## Output contract

```json
{"diagnostic_codes":[],"exit_code":0,"result":true,"schema":"TestValueCardValidationSummary/v1","status":"valid","validation_error_count":0,"validation_error_count_status":"MEASURED"}
```

The object has exactly these fields:

| Field | Meaning |
|---|---|
| `schema` | Stable contract identifier, `TestValueCardValidationSummary/v1`. |
| `status` | `valid`, `invalid`, or `unreadable`. |
| `result` | `true` only when the card was read and structurally valid. |
| `exit_code` | The command's numeric exit: 0 valid, 1 invalid, 2 unreadable input. |
| `diagnostic_codes` | Sorted, unique fixed codes; no user supplied text. |
| `validation_error_count` | Number of validator errors after a complete read, including measured zero; `null` when the card could not be read. |
| `validation_error_count_status` | `MEASURED` when the count is known; otherwise `NOT_MEASURED`. |

The object shape and status relationships are also available as the [Test Value Card Validation Summary JSON Schema](schemas/test-value-card-summary.v1.schema.json), using JSON Schema Draft 2020-12. The schema checks field structure, fixed diagnostic values, and status, result, exit-code, and availability-count relationships. The emitter sorts diagnostic codes; the schema checks their allowed values and uniqueness but does not enforce their order. This contract describes output shape, not whether a card is truthful, valuable, safe to change, or accepted.

Diagnostic codes describe structural validation only:

| Code | Meaning |
|---|---|
| `CARD_UNREADABLE` | The selected card could not be read; error count is unavailable. |
| `FRONTMATTER_REQUIRED` | YAML frontmatter is missing. |
| `FRONTMATTER_MALFORMED` | Frontmatter delimiters or structure are malformed. |
| `YAML_INVALID` | Frontmatter is not valid YAML. |
| `FRONTMATTER_NOT_MAPPING` | Parsed frontmatter is not a mapping. |
| `FIELD_TYPE_INVALID` | A required field is not a string. |
| `FIELD_TOO_LONG` | A field exceeds the existing 160 UTF-8 byte limit. |
| `FIELD_PLACEHOLDER` | A required field contains a placeholder. |
| `CAUSAL_EVIDENCE_INVALID` | The existing causal failure rule was not met. |
| `COVERAGE_GAP_UNSPECIFIED` | The existing coverage-gap rule was not met. |
| `SEAM_INVALID` | The existing seam rule was not met. |
| `VALIDATION_FAILED_GENERIC` | A validator error did not match a known diagnostic mapping. |

The summary does not measure whether a test is valuable, truthful, demanded, executed, or safe to change. It does not rank cards, run tests, select files, or authorize a test-plan action. It reports only the existing structural validator's result.
