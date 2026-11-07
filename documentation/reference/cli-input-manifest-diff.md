# Compare saved CLI input manifests

`dev-tools/compare-cli-input-manifests.py` compares two saved
`DatarimCliInputManifest/v1` JSON inventories. It reports added, removed, and
modified declarations without reopening the inventoried files or rerunning the
producer.

The comparison describes only the fields in the two saved records. It does not
verify that either record is authentic, that a declared digest matches a file,
or that an underlying file changed on disk. A `MODIFIED` result means the
declared digest or byte count differs.

Saved declarations do not identify the producer source revision or prove that a
producer invocation occurred. Check source review and delivery through their
own repository records; this comparison reports only the declarations supplied
to it.

## Run a comparison

Pass the two inventory files explicitly. Each must be a regular UTF-8 JSON file
no larger than 2 MiB. The command reads each input once and does not search for
other inputs.

```bash
set -euo pipefail
before_manifest="${BEFORE_MANIFEST:?set the earlier saved inventory path}"
after_manifest="${AFTER_MANIFEST:?set the later saved inventory path}"
python3 dev-tools/compare-cli-input-manifests.py \
  --before "$before_manifest" \
  --after "$after_manifest"
```

The utility uses only the Python standard library. It does not execute shell
commands, read files named inside the inventories, or make network requests.

## Accepted input records

Both inputs must be complete inventories with the producer's fixed schema,
successful result and exit code, measured file count, and a nonempty list of
file entries. Each entry must contain exactly a canonical relative POSIX path,
a lowercase 64-character SHA-256 digest, and a nonnegative byte count. Paths
must be unique and must not be absolute or contain empty, `.` or `..`
components. Each count is at most 1 MiB and the sum is at most 16 MiB; there may
be at most 64 entries.

The reader rejects invalid UTF-8, duplicate JSON keys, non-finite numbers,
unsupported or refused producer results, malformed fields, and input files over
the size limit. Integer-valued JSON decimals such as `3.0` are accepted for
`byte_count` using exact decimal parsing; booleans and fractional values are
not integers. Unknown top-level metadata fields are ignored for forward
compatibility. The entry shape remains exact.

Before opening either selected inventory, the utility requires the platform's
`O_NONBLOCK` open flag. If that capability is unavailable, it returns the fixed
input-refusal result before opening an input. This is a conditional capability
guard, not a claim that a FIFO hang or host failure was observed.

The command compares declarations only. It never treats an unavailable or
refused producer inventory as an empty inventory and never claims semantic
validation or hash truth.

## Output

Every handled comparison emits one JSON object with exactly these fields:

| Field | Meaning |
|---|---|
| `schema` | `DatarimCliInputManifestDiff/v1` |
| `result` | `UNCHANGED`, `CHANGED`, or `INPUT_REFUSED` |
| `exit_code` | `0` for unchanged, `1` for changed, `2` for a handled refusal |
| `diagnostic_codes` | Empty, `INPUT_MANIFEST_CHANGED`, or fixed `INPUT_MANIFEST_DIFF_REFUSED` code |
| `added_count` | Added declarations, or `null` when unavailable |
| `removed_count` | Removed declarations, or `null` when unavailable |
| `modified_count` | Modified declarations, or `null` when unavailable |
| `counts_status` | `MEASURED` or `NOT_MEASURED` |
| `changes` | Sorted change rows; empty for unchanged or refused inputs |

Each change row contains `relative_path`, `change`, `before_sha256`,
`after_sha256`, `before_byte_count`, and `after_byte_count`. The absent side of
an added or removed row is `null`. Paths are declared input data and may appear
in a changed result; JSON escaping keeps them literal. They are never executed.
Refusal output is fixed and does not echo paths, input values, or exception
messages. Refusals have three `null` counts, `NOT_MEASURED`, and no partial
changes. Argument-parser/help and output-stream failures occur outside the
handled JSON-result guarantee.

Exit `1` is an expected comparison result, not a tool failure. A shell caller
can preserve it separately from refusal and other command errors:

```bash
set -euo pipefail
before_manifest="${BEFORE_MANIFEST:?set the earlier saved inventory path}"
after_manifest="${AFTER_MANIFEST:?set the later saved inventory path}"
summary_file="${SUMMARY_FILE:?set the summary output path}"
if python3 dev-tools/compare-cli-input-manifests.py \
  --before "$before_manifest" --after "$after_manifest" > "$summary_file"; then
  status=0
else
  status=$?
fi
case "$status" in
  0) printf 'Declared inputs are unchanged.\n' ;;
  1) printf 'Declared inputs differ; inspect %s.\n' "$summary_file" ;;
  2) printf 'An input inventory was refused.\n' >&2; exit 2 ;;
  *) exit "$status" ;;
esac
```

## Roll back

If a reviewed change that added this tool must be withdrawn, inspect and revert
that exact commit on its branch:

```bash
set -euo pipefail
IFS=$'\n\t'
commit_to_revert="${COMMIT_TO_REVERT:?set the exact commit SHA to revert}"
if ! [[ "$commit_to_revert" =~ ^[0-9a-f]{40}$ ]]; then
  printf '%s\n' 'COMMIT_TO_REVERT must be a full lowercase commit SHA.' >&2
  exit 2
fi
git show --stat "$commit_to_revert"
git revert --no-edit "$commit_to_revert"
```

Inspect the exact commit and revert it on its feature branch through the normal
pull-request route. Do not use a broad reset to remove unrelated work.
