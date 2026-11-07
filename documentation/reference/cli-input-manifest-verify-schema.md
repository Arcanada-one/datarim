# CLI input manifest verification result schema

The [`DatarimCliInputManifestVerification/v1` schema](schemas/cli-input-manifest-verification.v1.schema.json) describes the fixed JSON object emitted by `dev-tools/verify-cli-input-manifest.py`. A Draft 2020-12 validator can check saved output structure and the fixed result profiles without opening selected files again.

## Validate a saved result

Use an installed Draft 2020-12 validator. For example, when the Python `jsonschema` package is already available:

```bash
set -euo pipefail
schema_file="documentation/reference/schemas/cli-input-manifest-verification.v1.schema.json"
result_file="/path/to/saved-verification.json"
python3 - "$schema_file" "$result_file" <<'PY'
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator

schema = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
result = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
Draft202012Validator.check_schema(schema)
Draft202012Validator(schema).validate(result)
PY
```

This example uses the validator only; the schema adds no runtime dependency to the producer. The validator must support Draft 2020-12.

## Fields and result profiles

Every object has exactly seven fields. Missing fields and additional fields are invalid.

| Field | Meaning |
|---|---|
| `schema` | Fixed identifier `DatarimCliInputManifestVerification/v1`. |
| `result` | `MATCHED`, `CHANGED`, or `INPUT_REFUSED`. |
| `exit_code` | Integer `0`, `1`, or `2`, correlated with the result. |
| `diagnostic_codes` | Empty for a match, or the one fixed code for changed/refused output. |
| `file_count` | Measured declared-file count from 1 through 64, or `null` when verification was refused. |
| `file_count_status` | `MEASURED` for completed file reads; otherwise `NOT_MEASURED`. |
| `changed_paths` | Unique relative paths with changed size or digest; empty for a match or refusal. |

| Result | Exit | Diagnostic codes | Count/status | Changed paths |
|---|---:|---|---|---|
| `MATCHED` | 0 | `[]` | Integer 1–64 / `MEASURED` | `[]` |
| `CHANGED` | 1 | `[INPUT_MANIFEST_BYTES_CHANGED]` | Integer 1–64 / `MEASURED` | 1–64 unique canonical relative paths |
| `INPUT_REFUSED` | 2 | `[INPUT_MANIFEST_VERIFICATION_REFUSED]` | `null` / `NOT_MEASURED` | `[]` |

The schema rejects wrong result/exit/code/count/status combinations, wrong JSON types, and unknown object fields. Draft 2020-12 treats a JSON number with an integer mathematical value such as `1.0` as an integer; booleans are not integers. This is not a claim about the original number's lexical spelling.

## Structural limits

The producer accepts unique canonical relative POSIX paths and refuses absolute paths, NUL, backslash, empty components, `.` and `..` components. The schema applies those same path exclusions without adding a general control-character ban. Its component checks cover line feeds rather than treating a final line feed as the end of a component or skipping later components after a line feed. For example, `dir/\n` and `dir/.\n` are allowed because their final components are nonempty and are not exactly `.` or `..`; `dir/\n//child` remains invalid because it contains an empty component. Here `\n` denotes a line-feed character. `uniqueItems` checks exact repeated path strings.

Portable JSON Schema does not express the relationship that the number of changed paths cannot exceed `file_count`, nor does this schema prove that `changed_paths` are sorted. A structurally valid result does not prove that its counts, paths, digests, or result are true of any files. It does not open files or repeat the byte verification.

The result is a bounded byte-verification report. Schema validation does not establish which producer version created it, that the producer actually ran, that its input declaration was accurate, or that source review, delivery, task acceptance, or runtime readiness occurred. Filesystem snapshot and concurrent-mutation limits remain those of the producer.

## Follow-up and rollback

Change this schema and its reference through a normal repository branch and pull request. Revert a later change through the usual protected pull-request process; do not alter a saved result to make it validate.
