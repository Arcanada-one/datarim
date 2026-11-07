# Select entries from a saved CLI input manifest

`dev-tools/select-cli-input-manifest.py` selects exact declarations from one saved `DatarimCliInputManifest/v1` document. It does not run the producer, inspect listed paths, or refresh their hashes or sizes. Its output describes the selected rows in the saved manifest; it is not evidence that those files still exist or still have the recorded bytes.

## Example

Pass the saved manifest on standard input and repeat `--file` for each exact path. Use the `--file=NAME` form when a valid path begins with a hyphen so argparse treats it as the option value:

```sh
set -euo pipefail
IFS=$'\n\t'

python3 dev-tools/select-cli-input-manifest.py \
  --file documentation/architecture/overview.md \
  --file tests/example.bats \
  --file=-leading-name \
  < saved-input-manifest.json
```

The selector requires one complete successful producer result and one to 64 distinct canonical relative POSIX paths. Requested paths must occur exactly in the manifest. The result contains the selected rows sorted by path, with their original `sha256` and `byte_count` declarations. Unknown top-level producer metadata is ignored for forward compatibility. Listed path strings are data: do not evaluate them as shell syntax or use them as authorization to open files.

## Bounds and refusal

The selector reads at most 2 MiB from standard input. A complete input has one to 64 unique rows, each with exactly `relative_path`, `sha256`, and `byte_count`; each declared size is an integer from 0 through 1 MiB and the declared total is at most 16 MiB. Integral JSON decimal values are accepted when exactly integral. Duplicate JSON keys, malformed UTF-8 or JSON, unavailable/inconsistent producer results, invalid paths, invalid digests, invalid sizes, duplicate requests, and absent requested paths are refused as a whole. There is no partial result.

For a data refusal, the command writes one fixed `INPUT_REFUSED` JSON result with `file_count: null`, `file_count_status: "NOT_MEASURED"`, and no files, writes the fixed diagnostic `INPUT_MANIFEST_SELECTION_REFUSED` to stderr, and exits 2. Successful selection exits 0 with a `COMPLETE` result and empty diagnostic list. Argparse help and argument-usage errors occur before manifest processing and use argparse's normal output and exit behavior; they are not data-refusal JSON.

## Safe use

Treat every path and digest as untrusted input data. This command neither shells out nor opens paths named by the manifest. Keep the saved manifest as the provenance source and retain the producer's original receipt separately. A selected summary does not establish current filesystem state, source approval, readiness, or task acceptance. The producer and selector have distinct roles and may be reviewed together in one repository change; the selected data does not replace those source-control checks.

## Rollback

To revert a committed selector change, pass its full commit SHA to this guarded command. It validates the SHA before using it and passes it as one quoted argument to `git revert`:

```sh
set -euo pipefail
IFS=$'\n\t'

if [[ ! "${1:-}" =~ ^[0-9a-f]{40}$ ]]; then
  printf 'Usage: %s FULL_COMMIT_SHA\n' "$0" >&2
  exit 2
fi

commit_sha=''
commit_sha="$1"
git revert "$commit_sha"
```

Review the resulting revert and deliver it through a follow-up pull request using the normal review and verification process. Do not rewrite shared history to roll back a published change.
