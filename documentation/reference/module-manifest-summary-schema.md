# Module-manifest summary schema and consumer reference

Use the portable [Draft 2020-12 schema](schemas/module-manifest-summary.v1.schema.json)
to validate a `DatarimModuleManifestSummary/v1` JSON result independently. The
schema checks the fixed object shape and source-supported result/count profiles;
it does not run the producer or validate the manifest itself.

## Fields

Every summary has exactly these eight fields:

| Field | Values | Meaning |
|---|---|---|
| `schema` | `DatarimModuleManifestSummary/v1` | Fixed format identifier. |
| `result` | `VALID`, `INVALID`, `INPUT_UNAVAILABLE` | The producer's completed structural result or handled missing-manifest result. |
| `exit_code` | `0`, `1`, `2` | The producer exit code represented by the result. |
| `diagnostic_codes` | `[]`, `["MODULE_MANIFEST_INVALID"]`, or `["MODULE_MANIFEST_UNAVAILABLE"]` | Fixed codes; dynamic manifest names, paths, and warnings are not included. |
| `skill_count` | Non-negative integer or `null` | Count measured by the existing structural pass, when it completes. |
| `skill_count_status` | `MEASURED`, `NOT_MEASURED` | Whether the producer completed that count. |
| `warning_count` | Non-negative integer or `null` | Number of existing warning calls made during a completed pass. |
| `warning_count_status` | `MEASURED`, `NOT_MEASURED` | Whether the producer completed that count. |

## Supported profiles

- **`VALID`** has exit code `0`, no diagnostic codes, a measured `skill_count`
  of at least `1`, and a measured non-negative `warning_count`. Existing
  warnings do not change the result, so a warning-only result remains `VALID`.
- **`INVALID`** has exit code `1`, code `MODULE_MANIFEST_INVALID`, and measured
  non-negative counts. A hard error can be an empty skills list, so this profile
  permits `skill_count: 0`.
- **`INPUT_UNAVAILABLE`** has exit code `2`, code
  `MODULE_MANIFEST_UNAVAILABLE`, and `null` counts with `NOT_MEASURED` statuses.
  This distinguishes unavailable input from a completed check that measured
  zero warnings or skills.

The schema requires the exact field set, JSON types, fixed values, and these
result/code/exit/count-availability correlations. JSON Schema's `integer` type
accepts mathematically integral JSON numbers such as `1.0`; booleans are not
integers.

## Limits

This schema checks structure and fixed cross-field profiles. It does not check
arithmetic relationships between counts, compare a count to manifest contents,
validate skill quality, parse YAML, resolve dependencies, or prove that a result
is truthful, secure, current, or produced by a particular runtime. The producer
uses an existing shell and awk structural approximation rather than a full YAML
parser. The schema describes the source-approved producer candidate's output
contract; it does not establish that the producer is present on current main,
published, or accepted.
