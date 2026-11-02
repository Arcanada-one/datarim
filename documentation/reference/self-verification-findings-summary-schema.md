# Self-verification findings summary schema

The [versioned JSON Schema](schemas/self-verification-findings-summary.v1.schema.json) defines the portable structure and result/count relationships for `DatarimSelfVerificationFindingsSummary/v1`. A consumer can validate a summary object with any validator that supports JSON Schema Draft 2020-12. The schema checks the summary shape; it does not rerun or replace the producer's validation.

## Fields

Each summary is a closed object with exactly eight required fields; additional properties are rejected:

| Field | Meaning |
|---|---|
| `schema` | Fixed format identifier, `DatarimSelfVerificationFindingsSummary/v1`. |
| `result` | `VALID`, `INVALID`, or `INPUT_REFUSED`. |
| `exit_code` | The corresponding completed validation or input-refusal exit code: `0` or `1`. |
| `diagnostic_codes` | Empty for `VALID`; `FINDINGS_INVALID` for `INVALID`; one fixed input-refusal code for `INPUT_REFUSED`. |
| `normalized_count` | Non-negative count when record normalization ran; otherwise `null`. |
| `normalized_count_status` | `MEASURED` when normalization supplied the count; otherwise `NOT_MEASURED`. |
| `malformed_count` | Non-negative rejected-record count when normalization ran; otherwise `null`. |
| `malformed_count_status` | `MEASURED` when normalization supplied the count; otherwise `NOT_MEASURED`. |

## Supported result profiles

| Result | Exit | Diagnostic codes | Normalized count | Malformed count |
|---|---:|---|---|---|
| `VALID` | `0` | `[]` | Non-negative integer, `MEASURED` | `0`, `MEASURED` |
| `INVALID` | `1` | `["FINDINGS_INVALID"]` | Non-negative integer, `MEASURED` | Positive integer, `MEASURED` |
| `INPUT_REFUSED` | `1` | Exactly one of `FINDINGS_JSON_INVALID` or `FINDINGS_SHAPE_INVALID` | `null`, `NOT_MEASURED` | `null`, `NOT_MEASURED` |

Zero is a measured value: it means the corresponding completed normalization path counted zero records. `null` with `NOT_MEASURED` means the producer refused the input before that count was available. These values are not interchangeable.

Under Draft 2020-12, a JSON number with no fractional part, such as `1.0`, satisfies the `integer` type. The schema checks each count's allowed type and profile relationship; it does not assert arithmetic across the two counts or a total count.

## Consumer use and limits

Load the schema and validate the decoded summary object with an installed Draft 2020-12 validator. Keep the producer's process exit code as a separate signal; schema validity confirms only that the emitted summary matches this structural contract.

The summary contains no finding text, evidence, paths, raw records, exception messages, arguments, or task identifiers. `normalized_count` reflects records accepted by the producer's existing normalization loop, including records that the producer may mark discarded under its current policy. This contract does not establish finding quality, security truth, totals outside the reported counts, or semantic correctness.

The documented profiles cover completed validation and the two input-refusal outcomes. They do not promise a summary for argument or usage errors, help output, signals, or other unhandled failures. The schema does not change producer behavior or establish that a particular producer version is present in a given installation.
