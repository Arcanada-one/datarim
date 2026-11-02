# Captured Summary Exit Rollup Schema

The [Draft 2020-12 JSON Schema](schemas/summary-exit-rollup.v1.schema.json) describes the fixed `DatarimSummaryExitRollup/v1` object emitted by the captured-summary exit rollup. Use it to check a saved JSON object without rerunning the checkers that produced its source summaries.

## Profiles

Every object has exactly seven fields. The schema rejects missing or additional fields and enforces these four result profiles:

| `result` | `exit_code` | `diagnostic_codes` | `summary_count` | `summary_count_status` | `exit_counts` |
|---|---:|---|---|---|---|
| `CLEAN` | `0` | `[]` | Integer from 0 through 256 | `MEASURED` | Object with exactly string keys `0`, `1`, and `2`; each value is an integer from 0 through 256; counts for `1` and `2` are zero; when `summary_count` is zero, count for `0` is also zero |
| `FINDINGS` | `1` | `["SUMMARY_FINDINGS_PRESENT"]` | Integer from 1 through 256 | `MEASURED` | Same three keys and value bounds; count for `1` is at least 1 and count for `2` is zero |
| `ERROR` | `2` | `["SUMMARY_ERROR_PRESENT"]` | Integer from 1 through 256 | `MEASURED` | Same three keys and value bounds; count for `2` is at least 1 |
| `INPUT_REFUSED` | `2` | `["SUMMARY_EXIT_ROLLUP_REFUSED"]` | `null` | `NOT_MEASURED` | `null` |

The `schema` field is always `DatarimSummaryExitRollup/v1`. JSON Schema's integer type is mathematical: `1.0` is an integer-valued JSON number for validation, while booleans are not integers.

## Validate a saved object

Run a Draft 2020-12-capable `jsonschema` installation from the repository root. The shell passes file names as quoted arguments. Keep validation failures generic when saved data may be sensitive; do not print the full instance or underlying parser/validator exception.

```bash
set -euo pipefail
IFS=$'\n\t'
schema_file='documentation/reference/schemas/summary-exit-rollup.v1.schema.json'
summary_file='path/to/saved-summary.json'
python3 - "$schema_file" "$summary_file" <<'PY'
import json
import sys
from jsonschema import Draft202012Validator
from jsonschema.exceptions import SchemaError, ValidationError

try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        schema = json.load(stream)
    Draft202012Validator.check_schema(schema)
except (OSError, UnicodeDecodeError, json.JSONDecodeError, SchemaError):
    raise SystemExit("exit-rollup schema could not be loaded or checked")
try:
    with open(sys.argv[2], encoding="utf-8") as stream:
        instance = json.load(stream)
    Draft202012Validator(schema).validate(instance)
except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValidationError):
    raise SystemExit("saved summary could not be parsed or does not match the exit-rollup schema")
print("saved summary matches the structural schema")
PY
```

This example validates the parsed object. A JSON parser that silently discards duplicate object keys cannot report that condition to the schema engine; use a parser with duplicate-key rejection when that byte-level property matters.

## Structural limits and provenance

The schema enforces the fixed empty `CLEAN` correlation: when `summary_count` is zero, all three exit counts are zero. It can also enforce field presence, types, other fixed values, profile correlations, key closure, and stated numeric bounds. A standard JSON Schema cannot express arbitrary arithmetic such as `summary_count` being equal to the sum of `exit_counts`, or the sum of those three counts being at most 256. A structurally valid instance may therefore still have inconsistent non-empty totals; check such arithmetic separately when a consumer requires it.

The profile design is based on pinned producer source only. The producer's separate saved-output consumer evidence remains incomplete; this schema and reference do not establish producer acceptance or installation. Validation also does not establish where an object came from, whether a checker ran, whether its result is truthful, or whether any task or work item was accepted. The schema is a reusable format contract; it is not a producer, an execution record, or an acceptance decision. Keep provenance and the original producer evidence alongside saved objects.

## Changes and recovery

To change this public contract, update the schema and this reference together in a reviewed follow-up pull request. If a released change must be reversed, preserve the relevant evidence and submit a reviewed revert; do not edit a protected branch directly.
