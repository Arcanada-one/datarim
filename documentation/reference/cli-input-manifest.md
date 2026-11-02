# CLI input file manifest

`dev-tools/hash-cli-inputs.py` emits a bounded SHA-256 inventory for files selected explicitly by the caller. It records the bytes read from each selected regular file; it does not scan a tree, choose defaults, validate the files' meaning, or prove that a producer or test ran.

## Select files

The command requires one root and at least one repeated `--file` argument. Each file value is a canonical relative POSIX path beneath that root. Absolute paths, empty components, `.` or `..` components, duplicate selections, symlinks, non-regular files, unreadable or missing files, changing metadata, and limit violations produce a refusal. The command never expands globs or reads unselected files.

```sh
set -euo pipefail
python3 dev-tools/hash-cli-inputs.py \
  --root "$PWD" \
  --file documentation/reference/cli-input-manifest.md \
  --file dev-tools/hash-cli-inputs.py
```

The selection is sorted by relative path for deterministic output. The utility reads each file's contents once through a file descriptor opened beneath the root with no-follow directory traversal. It checks file and directory metadata before and after reading to detect observable changes. This is not an atomic snapshot across several files and cannot detect every possible concurrent filesystem change.

## Limits and platform

The maximum selection is 64 files, 1 MiB per file, and 16 MiB total. The utility requires POSIX directory-file-descriptor support with `O_NOFOLLOW`, `O_DIRECTORY`, and `O_NONBLOCK`. It checks that all required flags are available before opening the root or any selected path. The final selected-file open includes `O_NONBLOCK`, so a path that changes to a FIFO between the regular-file check and `open` cannot make that open wait for a writer; the opened descriptor is still checked for a regular file and matching inode. On platforms without a required primitive, the command returns the fixed handled refusal rather than using an unsafe fallback. This conditional guard describes the open behavior; it is not a claim that every concurrent filesystem change is detected.

## JSON result

Every handled selection emits one JSON object with exactly these top-level fields:

| Field | Meaning |
|---|---|
| `schema` | `DatarimCliInputManifest/v1` |
| `result` | `COMPLETE` or `INPUT_REFUSED` |
| `exit_code` | `0` for a complete inventory, `2` for a handled refusal |
| `diagnostic_codes` | Empty for completion; otherwise the fixed `INPUT_MANIFEST_REFUSED` code |
| `file_count` | Selected file count, or `null` when not measured |
| `file_count_status` | `MEASURED` or `NOT_MEASURED` |
| `files` | Sorted entries on completion; an empty array on refusal |

Each completed file entry has exactly `relative_path`, lowercase SHA-256 `sha256`, and `byte_count`. A refusal returns no partial entries and does not echo absolute paths, raw exceptions, argv, or private input values. The fixed diagnostic label is also written to standard error on a handled refusal. Required-argument/help output and failures before the handled result boundary are standard CLI/tool failures; they are not guaranteed to produce the JSON object.

The inventory describes observed file bytes only. It is not a schema check, validation result, test result, immutable cross-file snapshot, acceptance record, or evidence of semantic truth. Validate inputs independently before using the inventory. If validation is a prerequisite for downstream work, preserve the validator's failure with a short-circuiting chain:

```sh
set -euo pipefail
python3 path/to/independent-validator.py --input "$INPUT" \
  && python3 dev-tools/hash-cli-inputs.py --root "$ROOT" --file "$RELATIVE_INPUT"
```

The producer accepts a backslash as an ordinary POSIX filename character.
`dev-tools/verify-cli-input-manifest.py` uses a stricter input-path rule and
refuses declarations containing a backslash. For a manifest intended for that
verifier, select files whose relative paths contain no backslash.

## Use the saved-manifest tools together

The following sequence records two explicit snapshots, selects disjoint
declarations, merges those declarations, compares the full snapshots, verifies
the later snapshot against its current root, and renders both saved results.
Set `BEFORE_ROOT`, `AFTER_ROOT`, and `WORK_DIR` to private paths you control.
The roots must contain the named regular files; the merge selections are
deliberately disjoint so the merger has no same-path conflict.

```bash
set -euo pipefail
IFS=$'\n\t'
before_root="${BEFORE_ROOT:?set BEFORE_ROOT}"
after_root="${AFTER_ROOT:?set AFTER_ROOT}"
work_dir="${WORK_DIR:?set WORK_DIR}"
mkdir -m 700 -p -- "$work_dir"

python3 dev-tools/hash-cli-inputs.py --root "$before_root" \
  --file alpha.txt --file shared.txt >"$work_dir/before.json"
python3 dev-tools/hash-cli-inputs.py --root "$after_root" \
  --file alpha.txt --file shared.txt --file new.txt >"$work_dir/after.json"

python3 dev-tools/select-cli-input-manifest.py --file shared.txt \
  <"$work_dir/before.json" >"$work_dir/before-selected.json"
python3 dev-tools/select-cli-input-manifest.py --file new.txt \
  <"$work_dir/after.json" >"$work_dir/after-selected.json"

python3 - "$work_dir/before-selected.json" "$work_dir/after-selected.json" \
  >"$work_dir/merge-input.json" <<'PY'
import json
import sys

values = []
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as stream:
        values.append(json.load(stream))
json.dump(values, sys.stdout, ensure_ascii=True, separators=(",", ":"))
sys.stdout.write("\n")
PY
python3 dev-tools/merge-cli-input-manifests.py \
  <"$work_dir/merge-input.json" >"$work_dir/merged.json"

if python3 dev-tools/compare-cli-input-manifests.py \
  --before "$work_dir/before.json" --after "$work_dir/after.json" \
  >"$work_dir/diff.json"; then
  diff_exit=0
else
  diff_exit=$?
fi
case "$diff_exit" in
  0|1) ;;
  *) exit "$diff_exit" ;;
esac

python3 dev-tools/verify-cli-input-manifest.py --root "$after_root" \
  <"$work_dir/after.json" >"$work_dir/verification.json"
python3 dev-tools/format-input-verification.py \
  <"$work_dir/verification.json" >"$work_dir/verification.txt"
if python3 dev-tools/format-cli-input-manifest-diff.py \
  <"$work_dir/diff.json" >"$work_dir/diff.txt"; then
  format_exit=0
else
  format_exit=$?
fi
test "$format_exit" -eq "$diff_exit"
```

The merger combines declarations and refuses conflicting declarations for the
same path; it does not read those paths. The comparison's exit `1` means the
saved declarations differ, not that verification failed. Verification exit
`0` means the explicitly listed later-snapshot bytes matched at that check.
The text renderers summarize those saved JSON results; they do not add
provenance or turn a comparison result into an acceptance decision.

## Roll back

If a reviewed change introducing this utility must be withdrawn, inspect the exact candidate first and revert only that commit on its feature branch:

```sh
set -euo pipefail
IFS=$'\n\t'
CANDIDATE_COMMIT="${CANDIDATE_COMMIT:?Set this to the exact reviewed commit SHA}"
if ! [[ "$CANDIDATE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    printf '%s\n' 'CANDIDATE_COMMIT must be a full lowercase 40-character commit ID.' >&2
    exit 2
fi
git show --stat "$CANDIDATE_COMMIT" --
git revert "$CANDIDATE_COMMIT"
```

Run the revert on the feature branch and submit it through the repository's normal pull-request process. Do not use a broad reset to remove unrelated work or revert directly on `main`.
