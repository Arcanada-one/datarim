# CLI input manifest summary schema

The [`DatarimCliInputManifest/v1` JSON Schema](schemas/cli-input-manifest.v1.schema.json) describes the fixed JSON shape emitted by `dev-tools/hash-cli-inputs.py` for a completed inventory or a handled input refusal. It lets an independent tool check the saved object without opening the inventoried files or rerunning the producer. The producer remains the source of inventory behavior.

## Profiles

Every object has exactly these seven top-level fields. Additional fields are rejected.

| Field | Contract |
|---|---|
| `schema` | `DatarimCliInputManifest/v1` |
| `result` | `COMPLETE` or `INPUT_REFUSED` |
| `exit_code` | Integer `0` for `COMPLETE`, integer `2` for `INPUT_REFUSED` |
| `diagnostic_codes` | Empty for `COMPLETE`; exactly `INPUT_MANIFEST_REFUSED` for `INPUT_REFUSED` |
| `file_count` | Integer from 1 through 64 when measured; `null` when not measured |
| `file_count_status` | `MEASURED` for `COMPLETE`; `NOT_MEASURED` for `INPUT_REFUSED` |
| `files` | One through 64 entries for `COMPLETE`; empty for `INPUT_REFUSED` |

Each completed entry has exactly three fields: `relative_path`, `sha256`, and `byte_count`. The path is a nonempty relative POSIX path: `/` separates components, and empty, `.` and `..` components are excluded. Backslash is allowed as an ordinary POSIX filename character. NUL is excluded. The producer also checks that each path can be encoded as UTF-8; a schema check applies to the parsed JSON value and does not establish the producer's input encoding or execution. The path constraint includes newline characters and checks the end of the whole string.

`sha256` must be 64 lowercase hexadecimal characters. `byte_count` is an integer from 0 through 1 MiB. Draft 2020-12 considers a JSON number with an integer mathematical value, such as `1.0`, to be an integer; the schema makes no claim about the spelling used in the original JSON text. Booleans are not integers for this schema.

## Structural limits

The schema checks field names, JSON types, fixed values, the two result profiles, and each entry's local shape. It does not check that `file_count` equals the number of `files` entries, that paths are unique across entries, that entries are sorted, or that their byte counts sum to the producer's 16 MiB aggregate limit. It cannot recompute a digest from an inventoried file, establish that the saved object came from a particular producer run or source revision, establish source review or delivery status, or establish semantic truth. Validate the inventory's provenance and intended use independently.

This schema describes the producer's exact seven-field output, so it rejects
unknown top-level fields. Saved-manifest consumers may accept additional
top-level metadata for forward compatibility while still validating the
required core fields. That consumer tolerance does not change the producer's
output shape; each `files` entry remains an exact three-field object.

JSON Schema validation is a structural consumer check, not a producer invocation, file check, test result, acceptance record, or proof of an atomic multi-file snapshot.

## Validate a saved summary

Use an installed Draft 2020-12 validator. The shell passes paths as quoted arguments; validation failure remains a nonzero command result.

```sh
set -euo pipefail
schema_path=documentation/reference/schemas/cli-input-manifest.v1.schema.json
summary_path=${SUMMARY_PATH:?set SUMMARY_PATH to the saved JSON summary}
python3 - "$schema_path" "$summary_path" <<'PY'
import json
import sys
from jsonschema import Draft202012Validator

with open(sys.argv[1], encoding="utf-8") as stream:
    schema = json.load(stream)
with open(sys.argv[2], encoding="utf-8") as stream:
    summary = json.load(stream)

Draft202012Validator.check_schema(schema)
Draft202012Validator(schema).validate(summary)
PY
```

The validator checks only the JSON values supplied to it. Keep the original producer exit status and output alongside the summary when those are needed for an independent decision.

## Roll back a reviewed change

Inspect the exact reviewed commit and prepare a narrow revert through the repository's normal protected pull request process. Pass the commit identifier through a variable rather than using an unquoted placeholder that the shell could parse as redirection.

```sh
set -euo pipefail
candidate_commit=${CANDIDATE_COMMIT:?set CANDIDATE_COMMIT to the reviewed commit SHA}
git show --stat --oneline "$candidate_commit"
```
