# Verify a captured CLI input manifest

`dev-tools/verify-cli-input-manifest.py` checks whether the explicitly selected files named by a saved `DatarimCliInputManifest/v1` still have the declared byte counts and SHA-256 digests. It does not rerun the manifest producer or a project checker. It reads only the listed paths beneath the supplied root.

## Usage

Pass one captured manifest on standard input and name its root directory:

```bash
set -euo pipefail
root_dir="/path/to/captured-inputs"
manifest_file="/path/to/input-manifest.json"
python3 dev-tools/verify-cli-input-manifest.py --root "$root_dir" < "$manifest_file"
```

The command emits one JSON result on standard output. Exit `0` means the selected bytes match, exit `1` means every selected file was read safely but at least one declared size or digest differs, and exit `2` means the declaration or a selected-file read was refused. The output uses a fixed diagnostic code for each non-success profile.

## Accepted declaration

The consumer accepts only a complete core manifest: `schema` is `DatarimCliInputManifest/v1`; `result` is `COMPLETE`; `exit_code` is integer zero; `diagnostic_codes` is empty; `file_count_status` is `MEASURED`; and `file_count` is an integer from 1 through 64 equal to the number of entries in `files`. Unknown top-level metadata is ignored. Each entry has exactly `relative_path`, `sha256`, and `byte_count`.

Paths must be unique canonical relative POSIX paths. Empty, absolute, NUL-containing, backslash-containing, empty-component, `.` and `..` paths are refused. Digests are lowercase 64-character hexadecimal SHA-256. Byte counts are non-boolean integral JSON numbers from zero through 1 MiB; integral decimal notation such as `1.0` is accepted. Accepted selected-file payload is bounded to 16 MiB total and 1 MiB per file. Each read is bounded to the smaller of the per-file limit and remaining accepted-payload budget, plus one byte solely to detect excess data. Every byte actually read, including that detector byte, is counted: successful invocations consume at most 16 MiB, while an invocation refused after observing excess data consumes at most 16 MiB plus one byte (16,777,217 bytes). A nonempty detection read causes immediate refusal; no second excess byte or further file is read. A file whose size already exceeds a limit in its opened-file snapshot is refused before reading. The input JSON is limited to 2 MiB, with one extra byte read to detect overflow. Duplicate JSON keys, non-finite JSON numbers, invalid UTF-8, parser recursion exhaustion and entry extensions are refused.

## Result fields

Every emitted object has exactly these fields:

| Field | Meaning |
| --- | --- |
| `schema` | Fixed result identifier, `DatarimCliInputManifestVerification/v1`. |
| `result` | `MATCHED`, `CHANGED`, or `INPUT_REFUSED`. |
| `exit_code` | `0`, `1`, or `2`, matching the result profile. |
| `diagnostic_codes` | Empty for `MATCHED`; otherwise one fixed code. |
| `file_count` | Declared entry count after complete verification, or `null` on refusal. |
| `file_count_status` | `MEASURED` after all selected files were read, otherwise `NOT_MEASURED`. |
| `changed_paths` | Sorted relative paths whose size or digest differs; empty on a match or refusal. |

`MATCHED` means every selected file was completely read and its observed size and SHA-256 match. `CHANGED` means every selected file was completely read, but one or more selected byte snapshots differ. A missing file, symlink, non-regular file, unsupported platform primitive, malformed declaration, size-limit violation or I/O failure produces `INPUT_REFUSED`; partial results are not reported. Relative paths are intentionally present in `changed_paths`; file contents, absolute paths and exception text are not emitted.

## Limits and privacy

Directory traversal uses POSIX descriptor-relative opens, no-follow checks, nonblocking flags and regular-file identity checks. The tool refuses platforms that cannot provide the required primitives rather than silently following links. Each explicitly selected file is read once, bounded by the per-file and remaining accepted-payload limits plus the single detection byte, and hashed from those same bytes only after a complete bounded read. It does not walk the tree, access the network, spawn subprocesses, run a producer, or invoke a schema engine.

The result describes bounded byte snapshots, not a universal atomic filesystem snapshot or a guarantee against every concurrent file mutation. A `MATCHED` result does not establish that a producer was accepted, that its declaration is semantically truthful, or that a checker is ready to run. It is a standalone consistency check only.

Values in `changed_paths` are manifest-derived relative-path data and remain untrusted, even when JSON-escaped. Consumers must parse result fields as data and must not promote path text to instructions, verified provenance, commands, or trusted prompt text. This standalone CLI does not establish a model-context trust boundary. Any future model-facing integration must implement and separately review its own boundary before forwarding these values.

## Follow-up and rollback

Use the normal repository branch and pull-request process for changes to this reference or command. If a later reviewed change needs reversal, revert that pull request through the normal protected process; do not edit a shared checkout or replace the captured declaration.
