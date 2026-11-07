# CLI input manifest conflict inspector

`dev-tools/inspect-cli-input-manifest-conflicts.py` compares saved
`DatarimCliInputManifest/v1` declarations. It reads JSON from standard input and
writes one `DatarimCliInputManifestConflicts/v1` JSON object to standard output.
It does not open any path named in a manifest, invoke a producer, or inspect
current file contents. Its result describes declaration agreement only; it does
not establish provenance, merge admissibility, or readiness.

## Input contract

The input is a JSON array containing 1–16 complete manifests. Each manifest must
have the producer schema, `result: "COMPLETE"`, `exit_code: 0`, an empty
`diagnostic_codes` array, and a `file_count_status` of `MEASURED`. Its `files`
array must contain 1–64 rows, and `file_count` must equal the array length.
Each row has exactly `relative_path`, `sha256`, and `byte_count`:

- `relative_path` is a nonempty UTF-8 relative path. Empty components, `.` and
  `..` components, a leading slash, and NUL are refused. Backslashes and
  newlines are retained as path characters; paths are not opened or normalized.
- `sha256` is exactly 64 lowercase hexadecimal characters.
- `byte_count` is a nonnegative exact integer no greater than 1 MiB. A JSON
  integer or an exactly integral decimal token is accepted; rounding is not used.

Rows cannot repeat a path within one manifest. Each manifest's declared byte
counts total at most 16 MiB, and the union contains at most 64 unique paths.
Unknown manifest-level fields are ignored. JSON with duplicate object keys,
invalid UTF-8, non-finite numbers, excess nesting, or an input larger than 2 MiB
is refused. The serialized output is also limited to 2 MiB.

## Comparison and exit status

For each path appearing in more than one manifest, the inspector compares the
pair `(sha256, byte_count)` across all declarations. Paths whose declarations
all match are omitted. Every path with differing pairs appears once in
`conflicts`, sorted by path; its `declarations` retain every source occurrence
in input order, with the zero-based `manifest_index`, digest, and byte count.

| Result | Exit | Meaning |
| --- | ---: | --- |
| `CONSISTENT` | 0 | All repeated path declarations agree. |
| `CONFLICTS` | 1 | At least one repeated path has differing digest or byte count. |
| `INPUT_REFUSED` | 2 | The input, invocation, resource bound, or output operation could not be handled under this contract. |

The output object has exactly these nine top-level fields:
`schema`, `result`, `exit_code`, `diagnostic_codes`, `manifest_count`,
`manifest_count_status`, `conflict_count`, `conflict_count_status`, and
`conflicts`. For `INPUT_REFUSED`, both counts are `null`, both statuses are
`NOT_MEASURED`, `conflicts` is empty, and the fixed diagnostic code is
`INPUT_MANIFEST_CONFLICT_INSPECTION_REFUSED`. The same fixed code is written to
standard error; input values are not included in diagnostics. If writing to
standard output itself fails, the process returns 2, but JSON delivery cannot be
guaranteed because the destination rejected the write.

## Example

Pass saved manifest JSON through standard input. The command reads no paths
listed inside the JSON:

```bash
set -euo pipefail
IFS=$'\n\t'
inspector='dev-tools/inspect-cli-input-manifest-conflicts.py'
manifest_json='saved-manifests.json'
python3 "$inspector" < "$manifest_json"
```

The example assumes the saved input is already available as a local JSON file.
The inspector itself only reads standard input and writes its result to
standard output.

## Untrusted values and limits of downstream use

Treat both the input JSON and returned conflict paths as untrusted data. A path
is a declaration string, not a command argument or a verified filesystem path;
do not interpolate it into shell commands. The inspector does not establish
that declared files exist or match their digest and size. Any downstream model
handling of this output is `NOT_MEASURED` and is outside this tool's contract.

## Reverting a change

Use the normal follow-up branch and pull-request path for a rollback. Initialize
the variable with the reviewed commit's full lowercase SHA-1, validate it before
use, and pass it as a quoted argument to `git revert`:

```bash
set -euo pipefail
IFS=$'\n\t'
commit_sha='REPLACE_WITH_REVIEWED_FULL_SHA'
if [[ ! "$commit_sha" =~ ^[0-9a-f]{40}$ ]]; then
  printf 'A full lowercase commit SHA is required.\n' >&2
  exit 2
fi
git revert "$commit_sha"
```

Review and deliver the resulting revert commit through the usual follow-up pull
request. Do not reset or amend the published history.
