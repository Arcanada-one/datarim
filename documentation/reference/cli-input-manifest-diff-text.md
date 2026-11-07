# Read a saved CLI input-manifest difference

`dev-tools/format-cli-input-manifest-diff.py` renders one saved
`DatarimCliInputManifestDiff/v1` JSON value as bounded text. It reads standard
input only. It does not rerun the comparison producer, open any path named in
the diff, inspect actual files, start another process, use a network or model,
or establish that either saved declaration is authentic or truthful.

The comparer and formatter are distinct tools in the saved-manifest workflow.
This formatter consumes only the supplied diff bytes. Its output does not prove
that a producer ran, that the compared declarations are authentic, or that any
source revision passed review or delivery.

## Use

Save the comparison result, then pass its bytes on standard input. The command
writes a report to the selected output file while preserving its exit status:

```bash
set -euo pipefail
IFS=$'\n\t'
saved_diff="${SAVED_DIFF:?set the saved diff path}"
summary_file="${SUMMARY_FILE:?set the report output path}"
if python3 dev-tools/format-cli-input-manifest-diff.py < "$saved_diff" > "$summary_file"; then
  format_exit=0
else
  format_exit=$?
fi
case "$format_exit" in
  0) printf '%s\n' 'Saved declarations are unchanged.' ;;
  1) printf '%s\n' 'Saved declarations differ; inspect the rendered report.' ;;
  2) printf '%s\n' 'The saved diff was refused or could not be rendered.' >&2; exit 2 ;;
  *) exit "$format_exit" ;;
esac
```

Both paths are quoted shell arguments. The formatter accepts no path option and
never opens the saved diff by name.

## Accepted profiles

The input must be one UTF-8 JSON object with exactly nine fields:
`schema`, `result`, `exit_code`, `diagnostic_codes`, `added_count`,
`removed_count`, `modified_count`, `counts_status`, and `changes`. The schema
value must be `DatarimCliInputManifestDiff/v1`.

| Saved result | Formatter exit | Counts | Changes |
| --- | ---: | --- | --- |
| `UNCHANGED` | 0 | Three measured zeros | Empty |
| `CHANGED` | 1 | Measured nonnegative integers, each at most 64; their sum equals the row-kind totals | 1–128 sorted unique rows |
| `INPUT_REFUSED` | 2 | Three `null` values with `NOT_MEASURED` | Empty |

Each changed row has exactly `relative_path`, `change`, `before_sha256`,
`after_sha256`, `before_byte_count`, and `after_byte_count`. `change` is
`ADDED`, `REMOVED`, or `MODIFIED`. Added rows have a null before side; removed
rows have a null after side; modified rows have both sides and a different
hash-or-size tuple. Hashes are lowercase 64-character SHA-256 strings. Known
byte counts are integers from zero through 1 MiB. For each side, no more than
64 known rows and no more than 16 MiB of known bytes are accepted. These limits
check only the changed rows represented in the saved diff; the formatter does
not infer any unreported unchanged files.

Paths must be unique, sorted canonical relative POSIX paths: they cannot be
empty, absolute, contain NUL, or contain empty, `.` or `..` components. A
backslash or newline may occur in a declared path. The formatter displays each
path as one ASCII JSON string literal on its row, so control characters and
newlines are escaped rather than emitted literally. Escaping is presentation
syntax only. Paths remain untrusted data and must not be executed, treated as
verified filesystem locations, or forwarded into model context as trusted
instructions.

Integral JSON decimal tokens are checked as exact `Decimal` values before
integer conversion; booleans, fractions, non-finite numbers, and out-of-range
values are refused. Input is limited to 2 MiB plus one detection byte. Duplicate
JSON keys, invalid UTF-8, excessive nesting, inconsistent profile fields,
malformed rows, and an output exceeding 128 KiB are refused.

## Refusal behavior and limits

For malformed, inconsistent, oversized, or unrenderable input, the formatter
exits 2, writes no standard output, and writes only
`INPUT_MANIFEST_DIFF_FORMAT_REFUSED` to standard error. A valid saved
`INPUT_REFUSED` result is different: it is rendered with its declared exit code
and explicit `NOT_MEASURED` counts. Valid profiles otherwise write no standard
error. Stream failures occur outside the handled-profile guarantee.

The text reports only declared fields. It does not confirm a producer run,
recompute hashes, inspect files, or turn a refusal into an empty diff. It is not
a model-trust boundary or a source of provenance.

## Roll back

If this tool is later shipped and must be withdrawn, inspect and revert only its
exact reviewed commit through the normal pull-request route. Set strict shell
handling, validate the full commit SHA, and quote it:

```bash
set -euo pipefail
IFS=$'\n\t'
commit_to_revert="${COMMIT_TO_REVERT:?set the exact reviewed commit SHA}"
if ! [[ "$commit_to_revert" =~ ^[0-9a-f]{40}$ ]]; then
  printf '%s\n' 'COMMIT_TO_REVERT must be a full lowercase commit SHA.' >&2
  exit 2
fi
git show --stat "$commit_to_revert"
git revert --no-edit "$commit_to_revert"
```

Do not use a broad reset to remove unrelated work.
