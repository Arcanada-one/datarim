# CLI input manifest difference schema

The [Draft 2020-12 schema](schemas/cli-input-manifest-diff.v1.schema.json)
defines the structure of saved `DatarimCliInputManifestDiff/v1` reports. It
describes a declaration comparison. It does not establish that a producer ran,
that a report is authentic, that a declared digest matches a file, or that an
underlying file changed. This data format does not record whether a producer
ran or whether a source revision passed review or delivery.

## Result profiles

Every report is a closed object with exactly nine required fields:
`schema`, `result`, `exit_code`, `diagnostic_codes`, `added_count`,
`removed_count`, `modified_count`, `counts_status`, and `changes`. Unknown
fields are rejected.

| `result` | Exit | `diagnostic_codes` | Counts | `counts_status` | `changes` |
|---|---:|---|---|---|---|
| `UNCHANGED` | 0 | `[]` | all three are `0` | `MEASURED` | empty |
| `CHANGED` | 1 | `INPUT_MANIFEST_CHANGED` | integers from 0 through 64; at least one is positive | `MEASURED` | 1–128 rows |
| `INPUT_REFUSED` | 2 | `INPUT_MANIFEST_DIFF_REFUSED` | all three are `null` | `NOT_MEASURED` | empty |

Each change row is also closed and has exactly six fields: `relative_path`,
`change`, `before_sha256`, `after_sha256`, `before_byte_count`, and
`after_byte_count`. `ADDED` rows have a null before-side and a valid after-side;
`REMOVED` rows have a valid before-side and a null after-side; `MODIFIED` rows
have both sides. Digests are lowercase 64-character SHA-256 strings. Byte
counts are integers from 0 through 1,048,576. A path is a nonempty relative
POSIX path: leading or trailing `/`, empty components, `.` or `..` components,
and NUL are rejected. Backslash and newline are permitted filename characters
under the producer's POSIX path rule; they are not treated as separators or
commands.

JSON Schema `integer` is mathematical: a numeric value such as `1.0` is accepted
as an integer, while a JSON boolean is not an integer. The schema checks the
parsed value, not the original number spelling or byte encoding. The producer's
strict UTF-8 input decoding is a separate boundary; an already-parsed schema
instance cannot prove how its source bytes were encoded.

## Structural limits

The schema correlates the three result profiles and each row's null-side rules.
It cannot express arbitrary arithmetic or provenance checks. A consumer must
not infer that the reported counts equal the number of rows of each `change`
kind, that paths are unique or sorted, that before/after reports really differ
as stated, that aggregate byte limits hold, or that a digest is true. Those
claims require comparison with the source manifests and their capture
provenance. The schema validates report shape only.

## Validate a saved report

Use an already-installed Draft 2020-12 validator. For example, with the Python
`jsonschema` package already available, pass explicit paths as quoted arguments:

```bash
set -euo pipefail
IFS=$'\n\t'
schema_file="${SCHEMA_FILE:?set the schema path}"
report_file="${REPORT_FILE:?set the saved report path}"
python3 - "$schema_file" "$report_file" <<'PY'
import json
import sys

from jsonschema import Draft202012Validator

with open(sys.argv[1], encoding="utf-8") as stream:
    schema = json.load(stream)
with open(sys.argv[2], encoding="utf-8") as stream:
    report = json.load(stream)

Draft202012Validator.check_schema(schema)
if not Draft202012Validator(schema).is_valid(report):
    raise SystemExit("saved report does not match the schema")
print("saved report matches the schema")
PY
```

The schema adds no validator dependency. A validator parses JSON before checking
it; callers that require duplicate-key detection or strict source-byte handling
must enforce those at their JSON-reading boundary. Validation does not rerun a
producer or open any path named in a report.

## Roll back a later reviewed change

If a future reviewed pull request needs to be withdrawn, inspect and revert its
exact commit on a follow-up branch, then use the repository's normal review and
merge process:

```bash
set -euo pipefail
IFS=$'\n\t'
commit_to_revert="${COMMIT_TO_REVERT:?set the reviewed commit SHA}"
if ! [[ "$commit_to_revert" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
  printf '%s\n' 'Invalid commit SHA.' >&2
  exit 2
fi
git show --stat "$commit_to_revert"
git revert "$commit_to_revert"
```

Do not use a broad reset to remove unrelated work.
